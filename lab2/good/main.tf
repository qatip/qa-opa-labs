provider "aws" {
  region = "eu-west-2"
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "good_example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  associate_public_ip_address = false

  tags = {
    Owner       = "qa-user"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}