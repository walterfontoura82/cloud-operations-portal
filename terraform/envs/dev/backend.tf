terraform {
  backend "s3" {
    bucket         = "cloud-operations-portal-tfstate-67bbcf73"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloud-operations-portal-tf-locks"
    encrypt        = true
  }
}
