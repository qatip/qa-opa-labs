terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = "eu-west-2"
  allowed_account_ids = ["503561439433"]

  default_tags {
    tags = {
      Owner     = "michael"
      Project   = "opa-terraform-demo"
      ManagedBy = "Terraform"
    }
  }
}

variable "ssh_cidr" {
  description = "IPv4 source permitted to reach SSH. Initially insecure for the OPA demo."
  type        = string
  default     = "0.0.0.0/0"
}

resource "aws_vpc" "demo" {
  cidr_block = "10.77.0.0/24"

  tags = {
    Name = "opa-terraform-demo-vpc"
  }
}

resource "aws_security_group" "demo" {
  name_prefix = "opa-ssh-demo-"
  description = "Security group for the OPA Terraform SSH demonstration"
  vpc_id      = aws_vpc.demo.id

  tags = {
    Name = "opa-terraform-demo-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.demo.id
  description       = "SSH access evaluated by OPA before deployment"
  cidr_ipv4         = var.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22

  tags = {
    Name = "opa-terraform-demo-ssh"
  }
}

output "security_group_id" {
  description = "Security group created by this demo"
  value       = aws_security_group.demo.id
}

output "ssh_source" {
  description = "IPv4 source permitted by the SSH rule"
  value       = var.ssh_cidr
}
