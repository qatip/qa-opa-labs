terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  kind_script_template = replace(file("${path.module}/install_gitops_kind.sh"), "\r", "")

  kind_script_raw = replace(
    local.kind_script_template,
    "__ARGO_ADMIN_PASSWORD__",
    var.argocd_admin_password
  )
}

# -----------------------------------------------------------------------------
# Data source: Ubuntu 22.04 LTS AMI (Jammy) – latest in region
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu_2204" {
  most_recent = true

  owners = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# VPC + Subnet (simple default-style network)
# If you already have a VPC/Subnet, you can replace this with data sources.
# -----------------------------------------------------------------------------
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "lab_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.100.10.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-subnet"
    Environment = var.environment
  }
}

resource "aws_route_table" "lab_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }

  tags = {
    Name        = "${var.project_name}-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "lab_rta" {
  subnet_id      = aws_subnet.lab_subnet.id
  route_table_id = aws_route_table.lab_rt.id
}

# -----------------------------------------------------------------------------
# Security Group – SSH + optional “lab ports” (you can trim/expand later)
# -----------------------------------------------------------------------------
resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for GitOps lab VMs"
  vpc_id      = aws_vpc.lab_vpc.id

  # SSH from your IP (recommended) – update var.allowed_ssh_cidr
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Optional: HTTP/HTTPS for UIs (ArgoCD via reverse proxy, Jenkins, etc.)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ui_cidr]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ui_cidr]
  }

  # Egress – allow all out
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Argo CD NodePort"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ui_cidr]
  }

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ui_cidr]
  }

  ingress {
    description = "AWX NodePort"
    from_port   = 30082
    to_port     = 30082
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ui_cidr]
  }


  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance: Automation Host (Jenkins / AWX later)
# -----------------------------------------------------------------------------
resource "aws_instance" "automation_host" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type = var.instance_type_map[var.size].automation
# instance_type          = var.automation_instance_type
  subnet_id              = aws_subnet.lab_subnet.id
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.volume_size_map[var.size].automation
    volume_type = "gp3"
  }


  # Optional: Wire in cloud-init for automation host
  user_data = file("${path.module}/cloud-init-automation.yaml")

  tags = {
    Name        = "${var.project_name}-automation-host"
    Role        = "automation"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance: GitOps Host (multiple kind clusters + Argo CD)
# -----------------------------------------------------------------------------
resource "aws_instance" "gitops_host" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type = var.instance_type_map[var.size].gitops
  subnet_id              = aws_subnet.lab_subnet.id
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.volume_size_map[var.size].gitops
    volume_type = "gp3"
  }

  user_data = templatefile(
    "${path.module}/cloud-init-gitops.tftpl",
    {
      script_b64 = base64encode(local.kind_script_raw)
      argocd_admin_passwd = var.argocd_admin_password
    }
  )

  tags = {
    Name        = "${var.project_name}-gitops-host"
    Role        = "gitops"
    Environment = var.environment
  }
}
