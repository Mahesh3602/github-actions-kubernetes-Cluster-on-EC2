################################
# Provider
################################
provider "aws" {
  region = "us-east-1"
}

#############################
# Terraform backend
#############################
terraform {
  backend "s3" {
    bucket         = "backed-bucket-11877"
    key            = "k8s/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }
}

################################
# Variables
################################
# These are now strings passed from GitHub Secrets
variable "public_key" {
  description = "The content of the SSH public key"
  type        = string
}

variable "private_key" {
  description = "The content of the SSH private key"
  type        = string
  sensitive   = true
}

################################
# Data Sources
################################
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  filter {
    name   = "name"
    values = ["*ubuntu-noble-24.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

################################
# Key Pair
################################
resource "aws_key_pair" "ec2_key" {
  key_name   = "my-terraform-key"
  public_key = var.public_key # Uses the variable string directly
}

################################
# Networking
################################
resource "aws_vpc" "k8s_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "k8s-vpc" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = { Name = "k8s-public-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

################################
# Security Group
################################
resource "aws_security_group" "k8s_sg" {
  name   = "k8s-sg"
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Internal cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.k8s_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# EC2 Instances
################################

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.ec2_key.key_name
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "control-plane-01" }
}

resource "aws_instance" "worker_01" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.ec2_key.key_name
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "worker-01" }
}

resource "aws_instance" "worker_02" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.ec2_key.key_name
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "worker-02" }
}

################################
# Automation: Inventory & SSH Wait
################################

# 1. Generate the inventory file automatically
resource "local_file" "ansible_inventory" {
  content  = <<EOT
[control_plane]
control-plane-01 ansible_host=${aws_instance.control_plane.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./id_rsa

[workers]
worker-01 ansible_host=${aws_instance.worker_01.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./id_rsa
worker-02 ansible_host=${aws_instance.worker_02.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./id_rsa
EOT
  filename = "${path.module}/k8s-ansible/inventory.ini"
}

# 2. Wait for SSH to be ready before finishing
resource "null_resource" "wait_for_ssh" {
  depends_on = [aws_instance.control_plane, aws_instance.worker_01, aws_instance.worker_02]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = var.private_key # Uses the variable string directly
      host        = aws_instance.control_plane.public_ip
    }
    inline = ["echo 'Instances are ready for Ansible!'"]
  }
}
