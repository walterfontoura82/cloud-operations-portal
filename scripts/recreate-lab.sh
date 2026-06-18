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