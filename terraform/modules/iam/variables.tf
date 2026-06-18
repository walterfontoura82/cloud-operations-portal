variable "github_org" {
  type        = string
  description = "GitHub organization or username"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "terraform_state_bucket" {
  type        = string
  description = "Terraform remote state bucket"
}

variable "terraform_lock_table" {
  type        = string
  description = "Terraform lock DynamoDB table"
}