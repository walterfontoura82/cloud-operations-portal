data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-sg"
  description = "Security group for lab EC2"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from anywhere - lab only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere - lab only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Zabbix Web"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Zabbix Server"
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-ec2-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_instance" "lab" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name

  user_data = <<-EOF
  #!/bin/bash
  set -e

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release git unzip

  install -m 0755 -d /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker

  usermod -aG docker ubuntu
  mkdir -p /home/ubuntu/monitoring

    cat <<'COMPOSE' > /home/ubuntu/monitoring/docker-compose.yml
    services:
    grafana:
        image: grafana/grafana-oss:latest
        container_name: grafana
        restart: unless-stopped
        ports:
        - "3000:3000"
        volumes:
        - grafana-data:/var/lib/grafana

    zabbix-postgres:
        image: postgres:16-alpine
        container_name: zabbix-postgres
        restart: unless-stopped
        environment:
        POSTGRES_USER: zabbix
        POSTGRES_PASSWORD: zabbixpass
        POSTGRES_DB: zabbix
        volumes:
        - zabbix-postgres-data:/var/lib/postgresql/data

    zabbix-server:
        image: zabbix/zabbix-server-pgsql:alpine-latest
        container_name: zabbix-server
        restart: unless-stopped
        environment:
        DB_SERVER_HOST: zabbix-postgres
        POSTGRES_USER: zabbix
        POSTGRES_PASSWORD: zabbixpass
        POSTGRES_DB: zabbix
        depends_on:
        - zabbix-postgres
        ports:
        - "10051:10051"

    zabbix-web:
        image: zabbix/zabbix-web-nginx-pgsql:alpine-latest
        container_name: zabbix-web
        restart: unless-stopped
        environment:
        ZBX_SERVER_HOST: zabbix-server
        DB_SERVER_HOST: zabbix-postgres
        POSTGRES_USER: zabbix
        POSTGRES_PASSWORD: zabbixpass
        POSTGRES_DB: zabbix
        PHP_TZ: America/Argentina/Cordoba
        depends_on:
        - zabbix-server
        - zabbix-postgres
        ports:
        - "8080:8080"

    zabbix-agent:
        image: zabbix/zabbix-agent2:alpine-latest
        container_name: zabbix-agent
        restart: unless-stopped
        environment:
        ZBX_HOSTNAME: docker-monitoring-lab
        ZBX_SERVER_HOST: zabbix-server
        depends_on:
        - zabbix-server
        privileged: true
        volumes:
        - /var/run/docker.sock:/var/run/docker.sock

    volumes:
    grafana-data:
    zabbix-postgres-data:
    COMPOSE

    chown -R ubuntu:ubuntu /home/ubuntu/monitoring

    cd /home/ubuntu/monitoring
    docker compose up -d
  EOF

  tags = {
    Name        = "${var.project_name}-${var.environment}-ec2-lab"
    Environment = var.environment
    Project     = var.project_name
  }
}