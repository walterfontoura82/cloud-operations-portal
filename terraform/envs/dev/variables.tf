variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "cloud-operations-portal"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "cloud-operations-portal-dev-key"
}
