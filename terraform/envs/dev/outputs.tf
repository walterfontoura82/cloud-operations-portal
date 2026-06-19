output "ec2_public_ip" {
  value = module.ec2.public_ip
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
output "github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}



# output "ec2_public_ip" {
#   description = "Public IP of the lab EC2 instance"
#   value       = aws_instance.lab.public_ip
# }

# output "s3_bucket_name" {
#   description = "Name of the lab S3 bucket"
#   value       = aws_s3_bucket.lab.bucket
# }

# output "vpc_id" {
#   description = "VPC ID"
#   value       = aws_vpc.main.id
# }