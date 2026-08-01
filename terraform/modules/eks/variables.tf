variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs where EKS will create worker nodes"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 2
}

variable "github_actions_role_arn" {
  description = "IAM role authorized to deploy workloads to EKS"
  type        = string
}
