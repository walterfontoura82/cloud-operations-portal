# Paso a paso del proyecto: Cloud Operations Portal – AWS DevOps Platform

## 1. Objetivo del proyecto

El objetivo del proyecto fue construir un laboratorio DevOps/Cloud real usando AWS, Terraform, Docker, GitHub Actions y buenas prácticas de CI/CD.

La idea no fue solamente crear una aplicación simple, sino armar un flujo parecido al que se usa en empresas:

```text
GitHub
   ↓
GitHub Actions
   ↓
OIDC
   ↓
AWS IAM Role
   ↓
Terraform / Docker / ECR
   ↓
Infraestructura y aplicación
```

El proyecto quedó orientado a demostrar conocimientos en:

- AWS
- Terraform
- Docker
- GitHub Actions
- OIDC
- IAM
- ECR
- EC2
- S3
- DynamoDB
- FastAPI
- Pytest
- Ruff
- CI/CD
- Troubleshooting

---

## 2. Nombre del proyecto

Nombre elegido:

```text
Cloud Operations Portal
```

Nombre sugerido para portfolio:

```text
Cloud Operations Portal – AWS DevOps Platform
```

Descripción recomendada:

> Proyecto personal orientado a prácticas DevOps y Cloud Engineering. Incluye infraestructura como código con Terraform, backend remoto en S3 con locking en DynamoDB, autenticación OIDC entre GitHub Actions y AWS, construcción y publicación automática de imágenes Docker en Amazon ECR, aplicación FastAPI con pruebas automatizadas y validaciones de calidad.

---

## 3. Estructura inicial del repositorio

Primero se creó la estructura base:

```text
cloud-operations-portal/
├── app/
├── docs/
│   └── screenshots/
├── k8s/
├── monitoring/
├── scripts/
├── terraform/
│   ├── bootstrap/
│   ├── envs/
│   │   └── dev/
│   └── modules/
│       ├── ec2/
│       ├── ecr/
│       ├── eks/
│       ├── iam/
│       ├── lambda/
│       ├── monitoring/
│       ├── rds/
│       ├── s3/
│       └── vpc/
├── .github/
│   └── workflows/
├── README.md
├── Makefile
└── .gitignore
```

Esta estructura permite separar claramente:

- Código de aplicación
- Infraestructura
- Scripts
- Workflows CI/CD
- Documentación
- Manifiestos Kubernetes futuros

---

## 4. Primera infraestructura con Terraform

### Objetivo

Crear infraestructura real en AWS:

```text
VPC
Subnet pública
Internet Gateway
Route Table
Security Group
EC2
S3 bucket
```

Inicialmente todo se hizo dentro de:

```text
terraform/envs/dev/
```

Archivos principales:

```text
providers.tf
variables.tf
main.tf
outputs.tf
terraform.tfvars
```

### Recursos creados

- `aws_vpc`
- `aws_subnet`
- `aws_internet_gateway`
- `aws_route_table`
- `aws_route`
- `aws_route_table_association`
- `aws_security_group`
- `aws_instance`
- `aws_s3_bucket`
- `random_id`

### Comandos usados

```bash
cd terraform/envs/dev
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## 5. Problema: EC2 sin Key Pair

### Problema

El primer plan de Terraform iba a crear la EC2 sin `key_name`.

Eso significaba que la instancia se iba a crear, pero no íbamos a poder entrar por SSH.

### Validación

Se revisó si existían key pairs en AWS:

```bash
aws ec2 describe-key-pairs \
  --region us-east-1 \
  --query 'KeyPairs[*].KeyName'
```

La respuesta fue:

```json
[]
```

### Solución

Se creó una key pair nueva:

```bash
mkdir -p ~/.ssh/aws-labs

aws ec2 create-key-pair \
  --region us-east-1 \
  --key-name cloud-operations-portal-dev-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem

chmod 400 ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem
```

Luego se agregó en Terraform:

```hcl
variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}
```

Y en la instancia:

```hcl
key_name = var.key_name
```

---

## 6. User Data para instalar Docker automáticamente

### Objetivo

Evitar instalar Docker manualmente en la EC2.

En lugar de entrar por SSH y ejecutar comandos a mano, se agregó `user_data` en Terraform para que la instancia nazca configurada.

### Qué instala el user_data

- Docker
- Docker Compose plugin
- Git
- curl
- unzip
- dependencias básicas

### Aprendizaje importante

`user_data` se ejecuta solamente en el primer arranque de la EC2.

Si se agrega o modifica después de que la instancia ya existe, no se ejecuta automáticamente.

### Problema encontrado

Se agregó `user_data`, pero al entrar a la instancia:

```bash
docker --version
```

respondía:

```text
Command 'docker' not found
```

### Causa

La EC2 ya existía antes de agregar `user_data`.

### Solución

Se recreó solo la EC2:

```bash
terraform taint aws_instance.lab
terraform apply
```

Después se validó:

```bash
docker --version
docker compose version
```

Resultado:

```text
Docker version 29.5.3
Docker Compose version v5.1.4
```

---

## 7. Refactor Terraform a módulos

### Objetivo

Pasar de una configuración simple a una estructura más profesional.

Antes:

```text
terraform/envs/dev/main.tf
```

Después:

```text
terraform/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   └── s3/
└── envs/
    └── dev/
```

### Módulos creados

#### VPC

```text
terraform/modules/vpc/
├── main.tf
├── variables.tf
└── outputs.tf
```

Recursos:

- VPC
- Subnet pública
- Internet Gateway
- Route Table
- Route
- Association

#### EC2

```text
terraform/modules/ec2/
├── main.tf
├── variables.tf
└── outputs.tf
```

Recursos:

- Security Group
- EC2
- AMI Ubuntu
- User Data

#### S3

```text
terraform/modules/s3/
├── main.tf
├── variables.tf
└── outputs.tf
```

Recursos:

- Bucket S3
- Random suffix

---

## 8. Problema: Terraform quería recrear todo al modularizar

### Problema

Después de mover recursos a módulos, Terraform quería crear recursos nuevos:

```text
Plan: 10 to add, 0 to change, 0 to destroy
```

### Causa

Terraform state todavía conocía los recursos con nombres viejos:

```text
aws_vpc.main
aws_instance.lab
aws_s3_bucket.lab
```

Pero el código nuevo los referenciaba como:

```text
module.vpc.aws_vpc.main
module.ec2.aws_instance.lab
module.s3.aws_s3_bucket.lab
```

Terraform pensaba que eran recursos distintos.

### Solución

Mover el state:

```bash
terraform state mv aws_vpc.main module.vpc.aws_vpc.main
terraform state mv aws_subnet.public module.vpc.aws_subnet.public
terraform state mv aws_internet_gateway.main module.vpc.aws_internet_gateway.main
terraform state mv aws_route_table.public module.vpc.aws_route_table.public
terraform state mv aws_route.internet_access module.vpc.aws_route.internet_access
terraform state mv aws_route_table_association.public module.vpc.aws_route_table_association.public
terraform state mv aws_security_group.ec2 module.ec2.aws_security_group.ec2
terraform state mv aws_instance.lab module.ec2.aws_instance.lab
terraform state mv aws_s3_bucket.lab module.s3.aws_s3_bucket.lab
terraform state mv random_id.bucket_suffix module.s3.random_id.bucket_suffix
```

Después:

```bash
terraform plan
```

El plan quedó limpio.

---

## 9. Problema: se aplicó Terraform y se duplicó parte de la infraestructura

### Problema

En un momento se ejecutó `apply` mientras el state todavía no estaba correctamente migrado.

Terraform creó una nueva VPC y otros recursos.

### Error posterior

La EC2 falló con:

```text
InvalidKeyPair.NotFound: The key pair 'cloud-operations-portal-dev-key' does not exist
```

### Causa

La key pair no existía en la cuenta/región actual.

### Solución

Se recreó la key pair y luego se aplicó de nuevo.

```bash
aws ec2 create-key-pair \
  --region us-east-1 \
  --key-name cloud-operations-portal-dev-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem
```

---

## 10. Problema: Permission denied por SSH

### Error

```text
Permission denied (publickey)
```

### Causa

La private key local no coincidía con la key pair usada por la EC2.

### Solución

Se eliminó y recreó la key pair en AWS y se recreó la EC2 con Terraform.

```bash
aws ec2 delete-key-pair \
  --region us-east-1 \
  --key-name cloud-operations-portal-dev-key

rm ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem
```

Luego se recreó la key y la EC2.

---

## 11. Monitoring con Docker Compose

### Objetivo

Levantar observabilidad con contenedores Docker.

Servicios:

```text
Grafana
Zabbix Server
Zabbix Web
PostgreSQL para Zabbix
Zabbix Agent 2
```

Archivo:

```text
monitoring/docker-compose.yml
```

### Puertos

```text
Grafana: 3000
Zabbix Web: 8080
Zabbix Server: 10051
```

### Credenciales

```text
Grafana: admin / admin
Zabbix: Admin / zabbix
```

---

## 12. Problema: permisos Docker

### Error

Al ejecutar:

```bash
docker ps
```

apareció:

```text
permission denied while trying to connect to the docker API
```

### Causa

El usuario `ubuntu` todavía no tenía activa la pertenencia al grupo `docker`.

### Solución

Usar temporalmente:

```bash
sudo docker ps
```

O cerrar sesión y volver a entrar para que tome el grupo:

```bash
exit
ssh -i ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem ubuntu@IP
```

También puede usarse:

```bash
newgrp docker
```

---

## 13. Problema: docker-compose.yml mal generado por user_data

### Error

```text
yaml: while scanning a simple key
could not find expected ':'
```

### Causa

El archivo `docker-compose.yml` generado por `user_data` quedó mal formateado.

### Solución temporal

Se reemplazó manualmente el compose dentro de la EC2 para validar los servicios.

Luego se dejó la idea de automatizarlo correctamente mediante Terraform/script.

### Validación

```bash
sudo docker compose up -d
sudo docker ps
```

Resultado esperado:

```text
grafana
zabbix-postgres
zabbix-server
zabbix-web
zabbix-agent
```

---

## 14. Terraform Backend Remoto

### Objetivo

No guardar el state localmente.

Arquitectura:

```text
Terraform
   ↓
S3 Bucket
   ↓
terraform.tfstate

DynamoDB
   ↓
State Lock
```

### Carpeta creada

```text
terraform/bootstrap/
├── main.tf
├── outputs.tf
└── providers.tf
```

### Recursos creados

- S3 bucket para state
- Versioning
- Server-side encryption
- Public access block
- DynamoDB table para locking

### Comandos

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

### Output

```text
terraform_state_bucket = "cloud-operations-portal-tfstate-xxxx"
terraform_lock_table = "cloud-operations-portal-tf-locks"
```

---

## 15. Configuración del backend remoto en dev

Archivo:

```text
terraform/envs/dev/backend.tf
```

Ejemplo:

```hcl
terraform {
  backend "s3" {
    bucket         = "cloud-operations-portal-tfstate-xxxx"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloud-operations-portal-tf-locks"
    encrypt        = true
  }
}
```

### Migración

```bash
terraform init -migrate-state
```

### Validación

```bash
terraform plan
```

Se verificó:

```text
Acquiring state lock...
No changes.
Releasing state lock...
```

---

## 16. Problema: backend S3 no existía

### Error

```text
S3 bucket "cloud-operations-portal-tfstate-xxxx" does not exist
```

### Causa

La cuenta AWS usada era un sandbox temporal de 2 horas. Al expirar, se borraban los recursos:

- Bucket de backend
- DynamoDB lock table
- VPC
- EC2
- IAM
- ECR

### Solución

Crear un script para recrear todo el laboratorio.

---

## 17. Script de recreación del laboratorio

Archivo:

```text
scripts/recreate-lab.sh
```

### Objetivo

Automatizar el flujo completo cuando el sandbox se borra.

El script hace:

```text
1. Verifica identidad AWS
2. Crea backend S3 + DynamoDB
3. Obtiene output del bucket y lock table
4. Crea/verifica EC2 Key Pair
5. Actualiza backend.tf
6. Inicializa Terraform dev
7. Aplica infraestructura dev
8. Muestra outputs y comando SSH
```

### Script final base

```bash
#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="us-east-1"
KEY_NAME="cloud-operations-portal-dev-key"
KEY_PATH="$HOME/.ssh/aws-labs/${KEY_NAME}.pem"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BOOTSTRAP_DIR="$ROOT_DIR/terraform/bootstrap"
DEV_DIR="$ROOT_DIR/terraform/envs/dev"

echo "==> Checking AWS identity..."
aws sts get-caller-identity

echo "==> Bootstrapping Terraform backend..."
cd "$BOOTSTRAP_DIR"
rm -rf .terraform
terraform init
terraform apply -auto-approve

STATE_BUCKET="$(terraform output -raw terraform_state_bucket)"
LOCK_TABLE="$(terraform output -raw terraform_lock_table)"

echo "==> Backend created:"
echo "Bucket: $STATE_BUCKET"
echo "Lock table: $LOCK_TABLE"

echo "==> Ensuring EC2 key pair exists..."
mkdir -p "$HOME/.ssh/aws-labs"

if aws ec2 describe-key-pairs \
  --region "$AWS_REGION" \
  --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair already exists in AWS: $KEY_NAME"
else
  echo "Creating key pair: $KEY_NAME"

  rm -f "$KEY_PATH"

  aws ec2 create-key-pair \
    --region "$AWS_REGION" \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' \
    --output text > "$KEY_PATH"

  chmod 400 "$KEY_PATH"

  echo "Key saved at: $KEY_PATH"
fi

echo "==> Updating backend.tf..."
cat > "$DEV_DIR/backend.tf" <<EOF
terraform {
  backend "s3" {
    bucket         = "$STATE_BUCKET"
    key            = "envs/dev/terraform.tfstate"
    region         = "$AWS_REGION"
    dynamodb_table = "$LOCK_TABLE"
    encrypt        = true
  }
}
EOF

echo "==> Deploying dev infrastructure..."
cd "$DEV_DIR"
rm -rf .terraform

terraform init -reconfigure

terraform apply \
  -var="key_name=$KEY_NAME" \
  -auto-approve

echo "==> Lab recreated successfully!"
terraform output

echo "==> SSH command:"
EC2_IP="$(terraform output -raw ec2_public_ip)"
echo "ssh -i $KEY_PATH ubuntu@$EC2_IP"
```

---

## 18. Problema: key_name tomó el valor yes

### Error

```text
InvalidKeyPair.NotFound: The key pair 'yes' does not exist
```

### Causa

Terraform pidió:

```text
var.key_name
Enter a value:
```

Y se respondió accidentalmente:

```text
yes
```

Terraform interpretó que el nombre de la key pair era `yes`.

### Solución

Pasar la variable explícitamente:

```bash
terraform apply \
  -var="key_name=cloud-operations-portal-dev-key" \
  -auto-approve
```

También se agregó un default en `variables.tf`:

```hcl
variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "cloud-operations-portal-dev-key"
}
```

---

## 19. Limpieza antes de subir a GitHub

### Problema

Se encontraron archivos sensibles o generados:

```text
terraform.tfstate
terraform.tfstate.backup
.terraform/
terraform.tfvars
.pem
venv/
```

### Solución

Se limpió:

```bash
rm -rf app/venv
rm -f terraform/bootstrap/terraform.tfstate
rm -rf terraform/bootstrap/.terraform
rm -rf terraform/envs/dev/.terraform
rm terraform/envs/dev/terraform.tfstate*
rm terraform/modules/ec2/cloud-operations-portal-dev-key.pem
```

### .gitignore

Se agregó:

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars

# SSH
*.pem

# Python
venv/
.venv/
__pycache__/
*.pyc

# IDE
.vscode/
.idea/

# Logs
*.log

# Backups
*.bkp
```

### Validación

```bash
find . -name "*.tfstate" -o -name "*.pem" -o -name ".terraform"
```

No debía devolver archivos del proyecto.

---

## 20. GitHub Actions: Terraform Plan

### Objetivo

Ejecutar Terraform automáticamente desde GitHub.

Workflow:

```text
.github/workflows/terraform-plan.yml
```

### Flujo

```text
Checkout
Setup Terraform
Configure AWS Credentials
Terraform Init
Terraform Format
Terraform Validate
Terraform Plan
```

### OIDC

Se configuró GitHub Actions para autenticarse contra AWS sin access keys.

Permisos del workflow:

```yaml
permissions:
  id-token: write
  contents: read
```

---

## 21. Módulo IAM para GitHub OIDC

### Recursos

```text
aws_iam_openid_connect_provider
aws_iam_role
aws_iam_policy
aws_iam_role_policy_attachment
```

### Objetivo

Permitir que GitHub Actions asuma un role en AWS:

```text
GitHub Actions
   ↓
OIDC
   ↓
AWS IAM Role
   ↓
Terraform
```

---

## 22. Problema: GitHub Actions sin credenciales AWS

### Error

```text
No valid credential sources found
```

### Causa

GitHub Actions intentaba ejecutar `terraform init`, pero no tenía permisos para acceder al backend S3.

### Solución

Crear IAM Role con OIDC y usar:

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::ACCOUNT_ID:role/cloud-operations-portal-github-actions-terraform-role
    aws-region: us-east-1
```

---

## 23. Problema: 403 al acceder al state en S3

### Error

```text
Unable to access object "envs/dev/terraform.tfstate"
StatusCode: 403 Forbidden
```

### Causa

El role de GitHub tenía permisos sobre un bucket viejo:

```text
cloud-operations-portal-tfstate-67bbcf73
```

Pero el backend usaba otro bucket:

```text
cloud-operations-portal-tfstate-8706a97d
```

### Solución

Actualizar el módulo IAM para usar el bucket correcto.

También se agregaron permisos:

```hcl
s3:GetObject
s3:PutObject
s3:DeleteObject
s3:ListBucket
s3:GetBucketLocation
```

---

## 24. Problema: OIDC provider no encontrado

### Error

```text
No OpenIDConnect provider found in your account for https://token.actions.githubusercontent.com
```

### Causa

El sandbox se había reiniciado y el OIDC provider había sido eliminado.

### Solución

Recrear la infraestructura dev con Terraform o con el script:

```bash
./scripts/recreate-lab.sh
```

Validar:

```bash
aws iam list-open-id-connect-providers
```

Debe aparecer:

```text
token.actions.githubusercontent.com
```

---

## 25. App FastAPI

### Objetivo

Crear una aplicación mínima para poder probar CI, Docker y ECR.

Archivos:

```text
app/
├── __init__.py
├── main.py
├── requirements.txt
└── tests/
    └── test_main.py
```

### main.py

```python
from fastapi import FastAPI

app = FastAPI(title="Cloud Operations Portal")


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/")
def root():
    return {"message": "Cloud Operations Portal API"}
```

### Endpoints

```text
GET /
GET /health
```

---

## 26. Lint con Ruff

### Qué es lint

Lint es una validación automática de calidad de código.

No ejecuta la aplicación.

Detecta problemas como:

- imports no usados
- errores de formato
- variables no usadas
- problemas de estilo

### Comando

```bash
ruff check app
```

Resultado esperado:

```text
All checks passed!
```

---

## 27. Tests con Pytest

### Qué son los tests

Los tests validan el comportamiento del código.

Ejemplo:

```python
def test_health_check():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

### Problema: ModuleNotFoundError main

Error:

```text
ModuleNotFoundError: No module named 'main'
```

### Causa

Pytest no encontraba el módulo `main.py`.

### Primer intento

Cambiar:

```python
from main import app
```

por:

```python
from app.main import app
```

### Segundo error

```text
ModuleNotFoundError: No module named 'app'
```

### Solución

Ejecutar con `PYTHONPATH=.` desde la raíz del repo:

```bash
PYTHONPATH=. app/venv/bin/pytest app/tests
PYTHONPATH=. app/venv/bin/ruff check app
```

### Resultado

```text
2 passed
All checks passed
```

---

## 28. GitHub Actions: App CI

Workflow:

```text
.github/workflows/app-ci.yml
```

### Flujo

```text
Checkout
Setup Python
Install dependencies
Lint
Tests
```

### Workflow final

```yaml
name: App CI

on:
  pull_request:
    paths:
      - 'app/**'

  push:
    branches:
      - main
    paths:
      - 'app/**'

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r app/requirements.txt

      - name: Lint
        run: PYTHONPATH=. ruff check app

      - name: Tests
        run: PYTHONPATH=. pytest app/tests
```

### Resultado

Workflow en verde:

```text
App CI ✅
```

---

## 29. Dockerfile de la aplicación

Archivo:

```text
app/Dockerfile
```

Contenido:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### .dockerignore

```text
venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
tests/
```

---

## 30. Prueba Docker local

### Build

```bash
cd app
docker build -t cloud-operations-portal:local .
```

### Run

```bash
docker run --rm -p 8000:8000 cloud-operations-portal:local
```

### Validación

```bash
curl http://localhost:8000/health
```

Resultado:

```json
{"status":"ok"}
```

---

## 31. Qué significa docker run --rm

`--rm` elimina automáticamente el contenedor cuando se detiene.

Ejemplo:

```bash
docker run --rm -p 8000:8000 cloud-operations-portal:local
```

Significa:

```text
Crear contenedor
Exponer puerto 8000
Ejecutar FastAPI
Al detenerlo, borrar el contenedor
```

---

## 32. Módulo Terraform ECR

### Objetivo

Crear un repositorio ECR para almacenar imágenes Docker.

Carpeta:

```text
terraform/modules/ecr/
├── main.tf
├── variables.tf
└── outputs.tf
```

### main.tf

```hcl
resource "aws_ecr_repository" "this" {
  name         = var.repository_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.repository_name
  }
}
```

### variables.tf

```hcl
variable "repository_name" {
  description = "ECR repository name"
  type        = string
}
```

### outputs.tf

```hcl
output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}
```

### Integración en dev

```hcl
module "ecr" {
  source = "../../modules/ecr"

  repository_name = "cloud-operations-portal"
}
```

### Output

```hcl
output "ecr_repository_url" {
  value = module.ecr.repository_url
}
```

### Resultado

```text
ecr_repository_url = "ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/cloud-operations-portal"
```

---

## 33. Problema: Module not installed

### Error

```text
Module not installed
```

### Causa

Se agregó un módulo nuevo (`ecr`), pero no se corrió `terraform init`.

### Solución

```bash
terraform init
terraform validate
terraform plan
```

---

## 34. Problema: sandbox borró backend otra vez

### Error

```text
S3 bucket does not exist
```

### Causa

La cuenta sandbox reinició y borró el bucket.

### Solución

Ejecutar:

```bash
./scripts/recreate-lab.sh
```

O manualmente:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

Luego actualizar `backend.tf` y aplicar `envs/dev`.

---

## 35. GitHub Actions: Docker Build and Push

Workflow:

```text
.github/workflows/docker-build.yml
```

### Objetivo

Construir la imagen Docker y subirla a ECR automáticamente.

### Flujo

```text
Checkout
Configure AWS Credentials
Login to Amazon ECR
Build Docker image
Tag Docker image
Push Docker image
```

### Arquitectura

```text
GitHub Push
   ↓
GitHub Actions
   ↓
OIDC
   ↓
AWS IAM Role
   ↓
Docker Build
   ↓
Amazon ECR
```

---

## 36. Problema: falta permiso ecr:GetAuthorizationToken

### Error

```text
not authorized to perform: ecr:GetAuthorizationToken
```

### Causa

El IAM Role de GitHub tenía permisos para Terraform, pero no para ECR.

### Solución

Agregar permisos ECR al IAM policy:

```hcl
statement {
  effect = "Allow"

  actions = [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:CompleteLayerUpload",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
    "ecr:DescribeRepositories",
    "ecr:BatchGetImage"
  ]

  resources = ["*"]
}
```

### Problema adicional

Al agregar el bloque, quedó fuera del `data "aws_iam_policy_document"` por una llave `}` mal ubicada.

Error:

```text
Unsupported block type "statement"
```

### Solución

Reemplazar el archivo completo `terraform/modules/iam/main.tf` por una versión limpia y correctamente cerrada.

---

## 37. Validación de permisos IAM

Se revisó la policy con:

```bash
aws iam get-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/cloud-operations-portal-github-actions-terraform-plan-policy \
  --version-id v1 \
  --query 'PolicyVersion.Document.Statement'
```

Se confirmó que antes no aparecían permisos ECR.

Luego se aplicó Terraform y se confirmó que los permisos quedaron agregados.

---

## 38. Resultado final del workflow Docker

En GitHub Actions se observó:

```text
Docker Build and Push #2 ✅
Docker Build and Push #3 ✅
```

Esto confirmó que funcionó:

```text
GitHub Actions
   ↓
OIDC
   ↓
AWS IAM Role
   ↓
Login ECR
   ↓
Docker Build
   ↓
Docker Push
```

---

## 39. Estado actual del proyecto

### Infraestructura

```text
Terraform modular ✅
VPC ✅
EC2 ✅
S3 ✅
IAM ✅
ECR ✅
Backend remoto S3 ✅
DynamoDB Lock ✅
```

### Aplicación

```text
FastAPI ✅
Endpoint /health ✅
Dockerfile ✅
Docker build local ✅
Docker run local ✅
```

### Calidad

```text
Ruff ✅
Pytest ✅
App CI ✅
```

### CI/CD

```text
Terraform Plan ✅
GitHub OIDC ✅
Docker Build ✅
Docker Push ECR ✅
```

### Observabilidad

```text
Grafana ✅
Zabbix ✅
PostgreSQL ✅
Zabbix Agent ✅
```

---

## 40. Comandos útiles

### Recrear laboratorio

```bash
./scripts/recreate-lab.sh
```

### Aplicar Terraform dev

```bash
cd terraform/envs/dev
terraform init -reconfigure
terraform validate
terraform plan
terraform apply -var="key_name=cloud-operations-portal-dev-key"
```

### Ver outputs

```bash
terraform output
```

### Conectar por SSH

```bash
ssh -i ~/.ssh/aws-labs/cloud-operations-portal-dev-key.pem ubuntu@EC2_PUBLIC_IP
```

### Ver Docker

```bash
docker ps
docker images
docker logs CONTAINER_NAME
```

### Probar app local

```bash
cd app
docker build -t cloud-operations-portal:local .
docker run --rm -p 8000:8000 cloud-operations-portal:local
curl http://localhost:8000/health
```

### Ejecutar tests

```bash
PYTHONPATH=. app/venv/bin/pytest app/tests
```

### Ejecutar lint

```bash
PYTHONPATH=. app/venv/bin/ruff check app
```

---

## 41. Buenas prácticas aplicadas

- No subir `.pem`
- No subir `terraform.tfstate`
- No subir `.terraform/`
- No subir `venv/`
- Usar `.gitignore`
- Usar backend remoto
- Usar locking con DynamoDB
- Usar módulos Terraform
- Usar GitHub Actions
- Usar OIDC en vez de access keys
- Separar CI de Terraform y Docker
- Hacer lint antes de tests
- Construir imagen Docker antes de deploy
- Publicar imagen en ECR
- Usar outputs de Terraform
- Validar cada cambio con `terraform plan`

---

## 42. Puntos donde fallamos y aprendizaje

### Fallo 1

Terraform quería recrear recursos al modularizar.

Aprendizaje:

> Cuando se mueven recursos a módulos, hay que mover el state con `terraform state mv`.

### Fallo 2

La EC2 no tenía key pair.

Aprendizaje:

> Para entrar por SSH, la EC2 debe tener un `key_name` asociado.

### Fallo 3

`user_data` no instaló Docker en una EC2 existente.

Aprendizaje:

> `user_data` corre solo al primer arranque.

### Fallo 4

Docker daba permiso denegado.

Aprendizaje:

> El usuario debe pertenecer al grupo `docker` o usar `sudo`.

### Fallo 5

YAML de Docker Compose mal generado.

Aprendizaje:

> Los heredocs en bash/user_data deben cuidarse mucho para no romper la indentación.

### Fallo 6

Backend S3 desapareció.

Aprendizaje:

> En sandbox temporal hay que tener scripts de recreación.

### Fallo 7

Terraform tomó `yes` como `key_name`.

Aprendizaje:

> No responder `yes` cuando Terraform pide una variable. Es mejor usar `-var` o valores default.

### Fallo 8

GitHub Actions no tenía credenciales AWS.

Aprendizaje:

> Para CI/CD profesional usar OIDC + IAM Role.

### Fallo 9

403 contra S3 backend.

Aprendizaje:

> El IAM Role debe tener permisos sobre el bucket exacto que usa el backend.

### Fallo 10

OIDC provider desapareció.

Aprendizaje:

> En sandbox temporal los recursos IAM también desaparecen.

### Fallo 11

Faltaban permisos ECR.

Aprendizaje:

> Login y push a ECR requieren permisos específicos como `ecr:GetAuthorizationToken` y `ecr:PutImage`.

### Fallo 12

Bloque IAM mal cerrado.

Aprendizaje:

> En Terraform, los bloques `statement` deben ir dentro de `data "aws_iam_policy_document"`.

---

## 43. Próximo sprint recomendado

### Deploy en EC2

Arquitectura:

```text
GitHub Actions
   ↓
Docker Build
   ↓
Push ECR
   ↓
SSH EC2
   ↓
docker pull
   ↓
docker run
   ↓
FastAPI online
```

Objetivo:

```text
http://EC2_PUBLIC_IP:8000/health
```

Resultado esperado:

```json
{"status":"ok"}
```

### Después

Roadmap recomendado:

```text
Deploy EC2
↓
Nginx reverse proxy
↓
CloudWatch logs
↓
RDS PostgreSQL
↓
Lambda
↓
Kubernetes local
↓
EKS
↓
Prometheus + Grafana
```

---

## 44. Resumen para portfolio

Texto corto:

> Cloud Operations Portal es una plataforma DevOps desarrollada como laboratorio cloud real en AWS. Implementa infraestructura como código con Terraform modular, backend remoto en S3 con locking en DynamoDB, autenticación OIDC entre GitHub Actions y AWS, pipelines CI/CD para validación de Terraform, pruebas automatizadas, linting, construcción de imágenes Docker y publicación en Amazon ECR.

Texto técnico:

> El proyecto incluye una API FastAPI contenerizada con Docker, pruebas automatizadas con Pytest, validación de código con Ruff, infraestructura AWS desplegada con Terraform, IAM Role con OIDC para GitHub Actions, repositorio ECR para imágenes Docker y un script de recreación para entornos sandbox temporales.

Tecnologías:

```text
AWS
Terraform
Docker
GitHub Actions
OIDC
IAM
S3
DynamoDB
EC2
ECR
FastAPI
Python
Pytest
Ruff
Grafana
Zabbix
Linux
Bash
```

---

## 45. Estado para continuar

Punto exacto donde quedamos:

```text
Terraform + Docker + ECR + CI/CD funcionando.
Docker Build and Push en GitHub Actions en verde.
```

Próximo paso:

```text
Crear deploy automático hacia EC2 usando la imagen de ECR.
```

