terraform {
  backend "s3" {
    bucket         = "cloud-operations-portal-tfstate-e2aed0e7"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloud-operations-portal-tf-locks"
    encrypt        = true
  }
}
