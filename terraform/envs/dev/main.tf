module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = var.environment
}

module "s3" {
  source = "../../modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

module "ec2" {
  source = "../../modules/ec2"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_id
  key_name     = var.key_name
}
module "iam" {
  source = "../../modules/iam"

  github_org             = "walterfontoura82"
  github_repo            = "cloud-operations-portal"
  aws_region             = var.aws_region
  terraform_state_bucket = "cloud-operations-portal-tfstate-67bbcf73"
  terraform_lock_table   = "cloud-operations-portal-tf-locks"
}




# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"]

#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }
# }

# resource "aws_vpc" "main" {
#   cidr_block           = "10.10.0.0/16"
#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-vpc"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_subnet" "public" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.10.1.0/24"
#   map_public_ip_on_launch = true

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-public-subnet"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-igw"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.main.id

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-public-rt"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_route" "internet_access" {
#   route_table_id         = aws_route_table.public.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.main.id
# }

# resource "aws_route_table_association" "public" {
#   subnet_id      = aws_subnet.public.id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_security_group" "ec2" {
#   name        = "${var.project_name}-${var.environment}-ec2-sg"
#   description = "Security group for lab EC2"
#   vpc_id      = aws_vpc.main.id

#   ingress {
#     description = "SSH from anywhere - lab only"
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   ingress {
#     description = "HTTP from anywhere - lab only"
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     description = "Allow all outbound traffic"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-ec2-sg"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_instance" "lab" {
#   ami                    = data.aws_ami.ubuntu.id
#   instance_type          = "t3.micro"
#   subnet_id              = aws_subnet.public.id
#   vpc_security_group_ids = [aws_security_group.ec2.id]
#   key_name               = var.key_name

#   user_data = <<-EOF
#   #!/bin/bash
#   set -e

#   apt-get update -y
#   apt-get upgrade -y

#   apt-get install -y ca-certificates curl gnupg lsb-release git unzip

#   install -m 0755 -d /etc/apt/keyrings

#   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
#   gpg --dearmor -o /etc/apt/keyrings/docker.gpg

#   chmod a+r /etc/apt/keyrings/docker.gpg

#   echo \
#   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
#   https://download.docker.com/linux/ubuntu \
#   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
#   tee /etc/apt/sources.list.d/docker.list > /dev/null

#   apt-get update -y

#   apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#   systemctl enable docker
#   systemctl start docker

#   usermod -aG docker ubuntu

#   docker --version
#   docker compose version
#   EOF

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-ec2-lab"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "aws_s3_bucket" "lab" {
#   bucket = "${var.project_name}-${var.environment}-${random_id.bucket_suffix.hex}"

#   tags = {
#     Name        = "${var.project_name}-${var.environment}-s3-lab"
#     Environment = var.environment
#     Project     = var.project_name
#   }
# }

# resource "random_id" "bucket_suffix" {
#   byte_length = 4
# }