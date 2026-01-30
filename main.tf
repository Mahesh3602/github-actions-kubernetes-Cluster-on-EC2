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
    bucket         = "backed-bucket-1187"
    key            = "k8s/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }
}

################################
# Variables
################################
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
  public_key = var.public_key 
}

################################
# Networking
################################
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "k8s-vpc" }
}

# Created 2 Public Subnets in different AZs
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = { 
    Name                               = "k8s-public-subnet-1"
    "kubernetes.io/role/elb"           = "1"          # Required for public LBs
    "kubernetes.io/cluster/kubernetes" = "shared"     # Required for Controller discovery
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = { 
    Name                               = "k8s-public-subnet-2"
    "kubernetes.io/role/elb"           = "1"
    "kubernetes.io/cluster/kubernetes" = "shared"
  }
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

# Associations for both subnets
resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
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
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "control-plane-01" }
}

resource "aws_instance" "worker_01" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.ec2_key.key_name
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "worker-01" }
}

resource "aws_instance" "worker_02" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.ec2_key.key_name
  # Placed in the 2nd subnet for HA
  subnet_id              = aws_subnet.public_subnet_2.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  tags                   = { Name = "worker-02" }
}

################################
# Automation: Inventory & SSH Wait
################################

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

resource "null_resource" "wait_for_ssh" {
  depends_on = [aws_instance.control_plane, aws_instance.worker_01, aws_instance.worker_02]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = var.private_key 
      host        = aws_instance.control_plane.public_ip
    }
    inline = ["echo 'Instances are ready for Ansible!'"]
  }
}
