# Cloud Operations Portal – AWS DevOps Platform

Cloud Operations Portal es un laboratorio DevOps completo sobre AWS. El proyecto
aprovisiona infraestructura con Terraform, valida una API FastAPI, construye y
versiona imágenes Docker, las publica en Amazon ECR y despliega automáticamente la
aplicación sobre Amazon EKS.

El objetivo es reproducir un flujo similar al utilizado en equipos de plataforma:

```text
Código
  ↓
GitHub Actions
  ↓
OIDC + AWS IAM
  ↓
Docker Build
  ↓
Amazon ECR
  ↓
Amazon EKS
  ↓
AWS Load Balancer
  ↓
FastAPI
```

El laboratorio también incluye una instancia EC2 con Grafana y Zabbix ejecutados
mediante Docker Compose.

## Estado del proyecto

El flujo fue validado de punta a punta:

- Terraform crea y consulta correctamente la infraestructura;
- GitHub Actions autentica en AWS sin access keys permanentes;
- Ruff y Pytest validan la aplicación;
- Docker publica imágenes `latest` y etiquetas inmutables por SHA;
- EKS ejecuta dos réplicas de FastAPI;
- Kubernetes realiza rolling updates automáticos;
- un AWS Load Balancer expone la API;
- los endpoints `/health` y `/version` se verifican después del despliegue;
- Grafana y Zabbix funcionan en la instancia EC2 de monitoreo.

## Diagrama de arquitectura

El diagrama editable con iconos oficiales de AWS está disponible en:

[Abrir arquitectura en Draw.io](docs/cloud-operations-portal.drawio)

```text
                         ┌──────────────────────────┐
                         │         GitHub           │
                         │  App CI / Docker / IaC   │
                         └────────────┬─────────────┘
                                      │ OIDC
                                      ▼
┌──────────────────────────────────── AWS ────────────────────────────────────┐
│                                                                            │
│  IAM Role ──────── ECR ───────────────────────► EKS                        │
│                    latest + commit SHA           │                          │
│                                                  ├─ FastAPI pod             │
│  S3 backend ────── Terraform                     ├─ FastAPI pod             │
│  S3 lockfile                                      │                          │
│                                                  ▼                          │
│                                           AWS Load Balancer                 │
│                                                                            │
│  VPC ── public subnets ── EC2                                              │
│                             ├─ Grafana                                     │
│                             └─ Zabbix                                      │
└────────────────────────────────────────────────────────────────────────────┘
```

## Tecnologías

- AWS: VPC, EC2, IAM, OIDC, S3, ECR, EKS y Elastic Load Balancing;
- Terraform;
- Kubernetes;
- Docker y Docker Compose;
- GitHub Actions;
- Python y FastAPI;
- Pytest y Ruff;
- Grafana y Zabbix;
- Linux y Bash.

## Estructura del repositorio

```text
cloud-operations-portal/
├── .github/workflows/
│   ├── app-ci.yml
│   ├── docker-build.yml
│   ├── deploy-eks.yml
│   └── terraform-plan.yml
├── app/
│   ├── tests/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── docs/
│   ├── cloud-operations-portal.drawio
│   └── troubleshooting/
├── k8s/
│   └── app.yaml
├── monitoring/
│   └── docker-compose.yml
├── scripts/
│   └── recreate-lab.sh
└── terraform/
    ├── bootstrap/
    ├── envs/dev/
    └── modules/
        ├── ec2/
        ├── ecr/
        ├── eks/
        ├── iam/
        ├── s3/
        └── vpc/
```

## Aplicación FastAPI

La aplicación expone tres endpoints principales:

| Endpoint | Propósito | Respuesta esperada |
|---|---|---|
| `/` | Identificación de la API | `{"message":"Cloud Operations Portal API"}` |
| `/health` | Readiness, liveness y validación del pipeline | `{"status":"ok"}` |
| `/version` | Versión funcional desplegada | `{"version":"1.0.0"}` |

FastAPI también publica documentación OpenAPI en `/docs`.

### Desarrollo local

Crear y activar un entorno virtual:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r app/requirements.txt
```

Ejecutar la API:

```bash
cd app
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Validar desde otra terminal:

```bash
curl http://localhost:8000/health
curl http://localhost:8000/version
```

### Calidad y pruebas

Desde la raíz del repositorio:

```bash
PYTHONPATH=. python -m pytest app/tests
python -m ruff check app
```

## Imagen Docker

Construcción local:

```bash
docker build -t cloud-operations-portal:local ./app
```

Ejecución:

```bash
docker run --rm -p 8000:8000 cloud-operations-portal:local
```

Validación:

```bash
curl http://localhost:8000/health
```

En CI se publican dos etiquetas en ECR:

```text
cloud-operations-portal:latest
cloud-operations-portal:<git-commit-sha>
```

El despliegue usa el SHA, lo que permite identificar exactamente qué commit está
ejecutando Kubernetes y evita depender de una etiqueta mutable.

## Infraestructura con Terraform

### Bootstrap

`terraform/bootstrap` crea los recursos necesarios para el backend:

- bucket S3 versionado;
- cifrado del bucket;
- bloqueo de acceso público;
- tabla DynamoDB conservada por compatibilidad con iteraciones anteriores.

El entorno actual utiliza locking nativo de S3 mediante:

```hcl
use_lockfile = true
```

### Entorno de desarrollo

`terraform/envs/dev` compone los módulos y crea:

- VPC con DNS habilitado;
- dos subnets públicas en distintas zonas de disponibilidad;
- Internet Gateway, route table y asociaciones;
- Security Groups;
- EC2 Ubuntu con Docker;
- bucket S3 del laboratorio;
- repositorio ECR con escaneo al publicar;
- provider OIDC para GitHub;
- rol y política de GitHub Actions;
- clúster EKS;
- Managed Node Group;
- roles IAM del control plane y los workers;
- EKS Access Entry para el pipeline de despliegue.

### Comandos habituales

```bash
cd terraform/envs/dev
terraform init -reconfigure
terraform fmt -check -recursive
terraform validate
terraform plan
```

Siempre se debe revisar el resumen antes de aplicar:

```text
Plan: X to add, Y to change, 0 to destroy.
```

Un reemplazo inesperado de EKS puede eliminar el clúster y sus workloads. No se debe
ejecutar `terraform apply` si aparecen `must be replaced`, `-/+` o destrucciones no
planificadas.

## Autenticación OIDC

GitHub Actions no almacena access keys de AWS. Los workflows solicitan un token OIDC
y asumen un rol IAM temporal:

```text
GitHub Actions
  ↓ token OIDC
AWS STS AssumeRoleWithWebIdentity
  ↓ credenciales temporales
Terraform / ECR / EKS
```

El rol puede:

- consultar la infraestructura durante `terraform plan`;
- acceder al backend S3;
- publicar imágenes en ECR;
- consultar EKS;
- autenticarse en Kubernetes mediante un EKS Access Entry.

Para simplificar el laboratorio, el rol de GitHub tiene una asociación
`AmazonEKSClusterAdminPolicy`. En producción debe utilizarse un rol de despliegue
separado y limitado al namespace y las operaciones necesarias.

## Kubernetes y EKS

`k8s/app.yaml` declara:

- namespace `cloud-operations-portal`;
- Deployment con dos réplicas;
- puerto de contenedor `8000`;
- readiness probe sobre `/health`;
- liveness probe sobre `/health`;
- requests y limits de CPU y memoria;
- Service de tipo `LoadBalancer` en el puerto `80`.

### Acceso al clúster

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name cloud-operations-portal-dev-eks
```

```bash
kubectl get nodes -o wide
kubectl get pods -n cloud-operations-portal
kubectl get service -n cloud-operations-portal
```

### Aplicación manual

Validar sin crear recursos:

```bash
kubectl apply --dry-run=client -f k8s/app.yaml
```

Aplicar y observar el rollout:

```bash
kubectl apply -f k8s/app.yaml
kubectl rollout status deployment/cloud-operations-portal \
  -n cloud-operations-portal \
  --timeout=5m
```

Verificar la imagen desplegada:

```bash
kubectl get deployment cloud-operations-portal \
  -n cloud-operations-portal \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

## Pipelines CI/CD

### App CI

Se activa cuando cambia `app/**`:

1. checkout;
2. Python 3.11;
3. instalación de dependencias;
4. Ruff;
5. Pytest.

### Docker Build and Push

Se activa después de cambios en la aplicación o en el workflow Docker:

1. autentica en AWS mediante OIDC;
2. obtiene dinámicamente el registry de ECR;
3. construye la imagen;
4. etiqueta con `latest` y el SHA;
5. publica ambas etiquetas.

### Terraform Plan

Se activa ante cambios en Terraform o en su workflow:

1. configura Terraform;
2. autentica en AWS mediante OIDC;
3. inicializa el backend remoto;
4. valida formato y configuración;
5. compara el código con los recursos reales.

Este workflow no aplica cambios automáticamente.

### Deploy to EKS

Se ejecuta después de un `Docker Build and Push` exitoso en `main` y también admite
ejecución manual:

1. asume el rol AWS;
2. selecciona el SHA generado por el workflow Docker;
3. configura `kubectl`;
4. obtiene la URI actual de ECR;
5. renderiza temporalmente el manifiesto con la imagen exacta;
6. ejecuta `kubectl apply`;
7. espera el rolling update;
8. consulta `/health` a través del Load Balancer.

El flujo automático completo es:

```text
Cambio en app/**
  ├─► App CI
  └─► Docker Build and Push
             ↓ success
       Deploy to EKS
             ↓
       Health check público
```

## Monitoreo en EC2

El `user_data` de la instancia instala Docker y levanta:

- Grafana en el puerto `3000`;
- PostgreSQL para Zabbix;
- Zabbix Server en `10051`;
- Zabbix Web en `8080`;
- Zabbix Agent 2.

Comprobaciones útiles:

```bash
docker --version
docker compose version
docker ps
cloud-init status
```

En un entorno de laboratorio, las interfaces quedan disponibles en:

```text
http://<EC2_PUBLIC_IP>:3000
http://<EC2_PUBLIC_IP>:8080
```

No deben mantenerse credenciales predeterminadas ni puertos administrativos abiertos
a Internet en un entorno productivo.

## Recrear un sandbox

`scripts/recreate-lab.sh` automatiza la reconstrucción cuando cambia la cuenta
temporal de AWS. El script:

1. verifica la identidad AWS activa;
2. crea el backend mediante Terraform bootstrap;
3. crea o reutiliza el key pair EC2;
4. actualiza `backend.tf`;
5. actualiza el bucket permitido por IAM;
6. reinicializa el backend;
7. recrea la infraestructura del laboratorio;
8. muestra los outputs y el comando SSH.

Antes de ejecutarlo:

```bash
aws sts get-caller-identity
```

Luego:

```bash
./scripts/recreate-lab.sh
```

El script realiza operaciones destructivas sobre recursos del laboratorio. Debe
usarse únicamente en una cuenta sandbox y después de revisar la cuenta activa.

Los workflows contienen el ARN de la cuenta sandbox. Cuando la cuenta cambia, se
deben actualizar los valores `role-to-assume` antes de publicar cambios.

## Troubleshooting

### `terraform plan`: No configuration files

Los archivos del entorno no están en `terraform/`, sino en:

```bash
cd terraform/envs/dev
terraform plan
```

### S3 devuelve `403 Forbidden`

Comprobar que el bucket de `backend.tf` coincida con el valor enviado al módulo IAM:

```bash
grep -n "bucket" terraform/envs/dev/backend.tf
grep -n "terraform_state_bucket" terraform/envs/dev/main.tf
```

### GitHub no puede asumir el rol

Verificar:

- número de cuenta del ARN;
- existencia del provider OIDC;
- trust policy del rol;
- organización y repositorio permitidos;
- permiso `id-token: write` del workflow.

La investigación histórica de OIDC está documentada en
[`docs/troubleshooting/fix_oidc.md`](docs/troubleshooting/fix_oidc.md).

### Pods en `ImagePullBackOff`

```bash
kubectl describe pod <pod> -n cloud-operations-portal
```

Comprobar la URI y etiqueta de ECR, además de la política
`AmazonEC2ContainerRegistryReadOnly` del node group.

### Load Balancer en `<pending>`

```bash
kubectl describe service cloud-operations-portal \
  -n cloud-operations-portal
```

Revisar eventos, subnets, rutas a Internet y permisos del clúster.

## Seguridad

Este repositorio representa un laboratorio y no una configuración de producción.
Antes de utilizar un diseño similar en un entorno real se debe:

- limitar los CIDR de los Security Groups;
- separar el rol de Terraform del rol de despliegue;
- reducir los permisos administrativos de EKS;
- usar subnets privadas para los worker nodes;
- administrar secretos con AWS Secrets Manager o External Secrets;
- habilitar logs del control plane;
- habilitar TLS y DNS para la aplicación;
- fijar versiones de imágenes de monitoreo;
- proteger Grafana y Zabbix con autenticación segura;
- evitar `force_delete = true` en ECR de producción.

## Costos y destrucción

EKS, el Managed Node Group, EC2 y el Load Balancer generan costos mientras están
activos. Al terminar una demostración, revisar primero el plan de destrucción:

```bash
cd terraform/envs/dev
terraform plan -destroy
```

Solo después de confirmar los recursos y la cuenta:

```bash
terraform destroy
```

El Load Balancer también puede eliminarse previamente junto con el Service:

```bash
kubectl delete -f k8s/app.yaml
```

No destruir el backend hasta haber eliminado o respaldado el estado del entorno.

## Resultado para portfolio

> Plataforma DevOps sobre AWS aprovisionada con Terraform. Implementa autenticación
> OIDC para GitHub Actions, backend remoto con locking en S3, CI con Ruff y Pytest,
> construcción y versionado de imágenes Docker en ECR, despliegue continuo con
> rolling updates sobre Amazon EKS, Load Balancer público y monitoreo mediante Grafana
> y Zabbix en EC2.

## Licencia y alcance

Proyecto personal de aprendizaje y portfolio. Los nombres de cuenta, endpoints y
recursos temporales pueden cambiar al recrear el laboratorio en un nuevo sandbox.
