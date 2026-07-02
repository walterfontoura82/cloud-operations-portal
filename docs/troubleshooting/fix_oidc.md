# Correccion de OIDC entre GitHub Actions y AWS

## Resumen

Los workflows de GitHub Actions no podían asumir el rol de AWS mediante OIDC.
El error principal era:

```text
Could not assume role with OIDC: No OpenIDConnect provider found in your account
for https://token.actions.githubusercontent.com/
```

La causa inicial fue que el workflow de Terraform utilizaba un ARN perteneciente
a una cuenta AWS diferente de aquella donde estaban creados el provider OIDC y el
rol IAM.

Después de corregir la cuenta aparecieron dos problemas independientes:

- una advertencia por Actions que todavía declaraban Node.js 20;
- un permiso de lectura de ECR faltante para ejecutar `terraform plan`.

Este documento describe cada problema, su diagnóstico y la solución aplicada.

## Arquitectura involucrada

GitHub Actions solicita un token OIDC a GitHub y lo intercambia por credenciales
temporales de AWS mediante `sts:AssumeRoleWithWebIdentity`.

El flujo es:

1. GitHub genera un token para el workflow.
2. `aws-actions/configure-aws-credentials` envía el token a AWS STS.
3. AWS busca el provider OIDC `token.actions.githubusercontent.com`.
4. AWS evalúa la trust policy del rol solicitado.
5. Si las condiciones coinciden, AWS entrega credenciales temporales.

Todos los elementos deben existir en la misma cuenta AWS:

- provider OIDC;
- rol IAM;
- trust policy;
- políticas asociadas al rol.

## Problema 1: cuenta AWS incorrecta

El workflow publicado de Terraform utilizaba este rol:

```yaml
role-to-assume: arn:aws:iam::011555819382:role/cloud-operations-portal-github-actions-terraform-role
```

Sin embargo, la infraestructura y el provider OIDC estaban en la cuenta:

```text
586789648037
```

AWS buscaba el provider OIDC en la cuenta `011555819382`, donde no existía. Por
eso devolvía `No OpenIDConnect provider found`, aunque Terraform tuviera un
recurso OIDC correctamente definido en el código.

### Solución

Se unificaron los workflows para usar el ARN correcto:

```yaml
role-to-assume: arn:aws:iam::586789648037:role/cloud-operations-portal-github-actions-terraform-role
```

También se verificó directamente en AWS que existieran:

- `arn:aws:iam::586789648037:oidc-provider/token.actions.githubusercontent.com`;
- el rol `cloud-operations-portal-github-actions-terraform-role`;
- la audiencia `sts.amazonaws.com`;
- las condiciones para la rama `main` y los pull requests.

La trust policy permite estos sujetos:

```hcl
values = [
  "repo:walterfontoura82/cloud-operations-portal:ref:refs/heads/main",
  "repo:walterfontoura82/cloud-operations-portal:pull_request"
]
```

## Problema 2: deprecación de Node.js 20

GitHub mostraba esta advertencia:

```text
Node 20 is being deprecated. This workflow is running with Node 24 by default.
```

Esta advertencia no causaba el error OIDC. Era un problema separado relacionado
con las versiones internas de las Actions.

### Solución

Se actualizaron las Actions de AWS Credentials:

```yaml
uses: aws-actions/configure-aws-credentials@v6
```

Después, los logs mostraron que la advertencia restante provenía de
`actions/checkout@v4`. Por eso se actualizó `checkout` en todos los workflows:

```yaml
uses: actions/checkout@v6
```

No se configuró `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true`, porque eso solo
habría postergado la migración utilizando una versión insegura de Node.js.

## Problema 3: Terraform Plan no se ejecutaba

El workflow de Terraform solo observaba cambios dentro de:

```yaml
paths:
  - 'terraform/**'
```

Por lo tanto, modificar únicamente `.github/workflows/terraform-plan.yml` no
disparaba una ejecución nueva. Reejecutar un run antiguo tampoco servía, porque
GitHub utilizaba el commit anterior que todavía contenía la cuenta incorrecta.

### Solución

Se agregó el propio workflow a los filtros y se habilitó la ejecución manual:

```yaml
on:
  workflow_dispatch:

  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'

  push:
    branches:
      - main
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'
```

Esto permite validar cambios del workflow y lanzarlo manualmente cuando sea
necesario.

## Problema 4: permiso de lectura de ECR faltante

Después de corregir OIDC, GitHub Actions logró asumir el rol. Terraform llegó a
consultar los recursos de AWS, pero falló al leer las etiquetas del repositorio
ECR:

```text
AccessDeniedException: not authorized to perform: ecr:ListTagsForResource
```

Este error confirmó que OIDC ya estaba funcionando: el mensaje identificaba una
sesión válida del rol `cloud-operations-portal-github-actions-terraform-role`.
El problema era ahora la política de permisos del rol.

### Solución

Se agregó la acción faltante al documento IAM:

```hcl
actions = [
  "ecr:GetAuthorizationToken",
  "ecr:BatchCheckLayerAvailability",
  "ecr:CompleteLayerUpload",
  "ecr:InitiateLayerUpload",
  "ecr:PutImage",
  "ecr:UploadLayerPart",
  "ecr:DescribeRepositories",
  "ecr:ListTagsForResource",
  "ecr:BatchGetImage"
]
```

También se consolidaron dos bloques ECR duplicados en una sola declaración.

Para destrabar el pipeline se aplicó exclusivamente la política IAM:

```bash
terraform -chdir=terraform/envs/dev apply \
  -input=false \
  -auto-approve \
  -target=module.iam.aws_iam_policy.github_actions_terraform_plan
```

El resultado fue:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

No se aplicó el resto del plan ni se destruyeron recursos.

## Problema 5: lock concurrente de Terraform

Al modificar el workflow se dispararon casi simultáneamente una ejecución del
pull request y otra de `main`. Una tomó el lock de DynamoDB y la otra falló con:

```text
Error acquiring the state lock
ConditionalCheckFailedException
```

Este error no era de OIDC ni de permisos. Era la protección normal de Terraform
para impedir que dos procesos operaran sobre el mismo estado al mismo tiempo.
Cuando se ejecutó un único plan después de aplicar el permiso ECR, el check pasó.

## Sincronización de la rama main

La rama `main` local estaba un commit por delante y dos por detrás de
`origin/main`. El commit local era vacío y se había creado para intentar disparar
el workflow, pero los filtros por rutas impedían que eso funcionara.

Para conservar todo antes de sincronizar se realizó este procedimiento:

1. Se creó una rama de respaldo para el commit local.
2. Se guardaron temporalmente los archivos modificados con `git stash`.
3. Se alineó `main` con `origin/main`.
4. Se restauraron los cambios locales.
5. Después de los merges, se actualizó `main` mediante fast-forward.

Los cambios locales no relacionados no fueron descartados ni incluidos en los
commits de los workflows.

## Validaciones realizadas

Se comprobaron los siguientes puntos:

- identidad y cuenta AWS mediante STS;
- existencia y configuración del provider OIDC;
- trust policy del rol IAM;
- sintaxis de los scripts Bash;
- formato y validación de Terraform;
- inicialización del backend remoto;
- ejecución local de `terraform plan`;
- autenticación OIDC desde GitHub Actions;
- login en ECR;
- construcción de la imagen Docker;
- publicación de la etiqueta `latest` en ECR;
- ejecución exitosa de Terraform Plan desde GitHub Actions.

## Resultado final

La configuración final utiliza:

```yaml
uses: actions/checkout@v6
uses: aws-actions/configure-aws-credentials@v6
```

Y el rol correcto:

```yaml
role-to-assume: arn:aws:iam::586789648037:role/cloud-operations-portal-github-actions-terraform-role
```

Resultados comprobados:

- OIDC autentica correctamente;
- los workflows ejecutan Actions compatibles con Node.js 24;
- Docker construye y publica imágenes en ECR;
- Terraform puede leer el repositorio ECR;
- Terraform Plan termina exitosamente;
- `main` local y remoto quedaron sincronizados.

## Ejecuciones de referencia

- Docker Build and Push exitoso:
  <https://github.com/walterfontoura82/cloud-operations-portal/actions/runs/27852092990>
- Terraform Plan exitoso:
  <https://github.com/walterfontoura82/cloud-operations-portal/actions/runs/27852709751>

## Advertencia pendiente

Terraform informa que el parámetro `dynamodb_table` del backend está deprecado y
recomienda `use_lockfile`. Esta advertencia no bloquea OIDC ni los planes actuales,
pero conviene migrar el backend en una tarea separada y controlada.
