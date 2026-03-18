variable "aws_region" {
  description = "AWS region to deploy the lab VMs in"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Prefix for naming AWS resources"
  type        = string
  default     = "gitops-lab"
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "training"
}

variable "ssh_key_name" {
  description = "Name of an existing AWS EC2 key pair to use for SSH"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the VMs (use your public IP/CIDR)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_ui_cidr" {
  description = "CIDR allowed to access HTTP/HTTPS UIs exposed on the VMs"
  type        = string
  default     = "0.0.0.0/0"
}

# Instance sizes
variable "automation_instance_type" {
  description = "EC2 instance type for the Automation Host (Jenkins/AWX)"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16GB RAM
}

variable "gitops_instance_type" {
  description = "EC2 instance type for the GitOps Host (kind clusters + ArgoCD)"
  type        = string
  default     = "t3.xlarge" # bump to t3.2xlarge if you want more clusters
}

# Root volume sizes
variable "automation_root_volume_size_gb" {
  description = "Root disk size (GB) for Automation Host"
  type        = number
  default     = 100
}

variable "gitops_root_volume_size_gb" {
  description = "Root disk size (GB) for GitOps Host"
  type        = number
  default     = 150
}

variable "size" {
  description = "Overall lab VM sizing profile: small, medium, large"
  type        = string
  default     = "small"
}

variable "instance_type_map" {
  description = "Maps size → instance types for automation + gitops hosts"
  type = map(object({
    automation = string
    gitops     = string
  }))

  default = {
    small = {
      automation = "t3.small"
      gitops     = "t3.small"
    }
    medium = {
      automation = "t3.medium"
      gitops     = "t3.medium"
    }
    large = {
      automation = "t3.medium"
      gitops     = "t3.xlarge"
    }
  }
}

variable "volume_size_map" {
  description = "Maps size → root volume sizes for automation + gitops hosts"
  type = map(object({
    automation = number
    gitops     = number
  }))

  default = {
    small = {
      automation = 30
      gitops     = 50
    }
    medium = {
      automation = 50
      gitops     = 80
    }
    large = {
      automation = 100
      gitops     = 150
    }
  }
}

variable "argocd_admin_password" {
  description = "Initial Argo CD admin password configured in the platform cluster."
  type        = string
  default     = "Admin123!"  # for the lab; can be overridden
  sensitive   = true
}


