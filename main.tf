terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.26.0"
    }

    # docker = {
    #   source  = "kreuzwerker/docker"
    #   version = "2.20.2"
    # }
  }
}

# -----------------------------------------------------------------------------
# START PROVIDERS
# -----------------------------------------------------------------------------
provider "aws" {
  region = "us-east-1"

  shared_credentials_files = [
    "~/.aws/credentials"
  ]

  profile = "default"
}

# provider "docker" {}

# -----------------------------------------------------------------------------
# END PROVIDERS
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# START VARIABLES
# -----------------------------------------------------------------------------

variable "host_os" {
  type = string
}

variable "app-name" {
  type    = string
  default = "emoji_app"
}

variable "vpc-cidr" {
  type    = string
  default = "192.168.0.0/20"
}

variable "DOCKER_PASSWORD" {
  type = string
}
# -----------------------------------------------------------------------------
# END VARIABLES
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# START LOCAL
# -----------------------------------------------------------------------------
locals {
  nginx_conf_text = base64encode(templatefile("./nginx.tpl.conf", {
    instance0 = aws_instance.emoji_app[0].private_ip
    instance1 = aws_instance.emoji_app[1].private_ip
  }))

  ssh_key = file("~/.ssh/mtc-key.pub")
}
# -----------------------------------------------------------------------------
# END LOCALS
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# START DATA
# -----------------------------------------------------------------------------
data "cloudinit_config" "user_data_lb" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = templatefile("./cloud-init-lb.yaml", {
      nginx_conf_text = local.nginx_conf_text,
    })
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "/tmp/example.sh"
    content      = <<-EOF
      #!/bin/bash
      echo "Hello World"
    EOF
  }
}
data "cloudinit_config" "user_data_app" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = templatefile("cloud-init-app.tpl.yaml", {
      ssh_key         = local.ssh_key
      DOCKER_PASSWORD = var.DOCKER_PASSWORD
    })
  }
}

data "aws_ami" "server_ami" {
  most_recent = true
  owners = [
    "099720109477"
  ]

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
    ]
  }
}
# -----------------------------------------------------------------------------
# END DATA
# -----------------------------------------------------------------------------

resource "aws_vpc" "emoji_app_vpc" {
  cidr_block           = var.vpc-cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.app-name}_vpc"
  }
}

resource "aws_subnet" "emoji_app_subnet-1a" {
  vpc_id                  = aws_vpc.emoji_app_vpc.id
  cidr_block              = var.vpc-cidr
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "${var.app-name}-public-subnet"
  }
}

resource "aws_internet_gateway" "emoji_app_internet_gateway" {
  vpc_id = aws_vpc.emoji_app_vpc.id

  tags = {
    Name = "${var.app-name}-igw"
  }
}

resource "aws_route_table" "emoji_app_public_rt" {
  vpc_id = aws_vpc.emoji_app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.emoji_app_internet_gateway.id
  }

  tags = {
    Name = "${var.app-name}-public-rt"
  }
}

resource "aws_route_table_association" "emoji_app_public_rt_assoc" {
  subnet_id      = aws_subnet.emoji_app_subnet-1a.id
  route_table_id = aws_route_table.emoji_app_public_rt.id
}

# The aws default security group created for every vpc - this entry puts it
# under mnagement of terraform. By default, inbound traffic is only allowed
# from machines attached to this security group (denoted by `self = true`). We
# now modify this ingress rule to let in traffic from any machine within the
# VPC
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.emoji_app_vpc.id

  ingress {
    protocol = -1
    # This security group is the source of inbound traffic
    # self      = true
    from_port = 0
    to_port   = 0

    # There is no cidr_blocks entry in the default config. We put it here
    # because we need to modify the default config
    cidr_blocks = [
      var.vpc-cidr
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

resource "aws_security_group" "emoji_app_public_sg" {
  name        = "${var.app-name}-public-sg"
  description = "${var.app-name} public security group"
  vpc_id      = aws_vpc.emoji_app_vpc.id

  ingress {
    description = "SSH from allowed IP address list"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    description = "Allow http traffic on public subnet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "${var.app-name}-public-sg"
  }
}

resource "aws_key_pair" "mtc_auth" {
  key_name   = "mtckey"
  public_key = local.ssh_key
}

resource "aws_instance" "emoji_app-lb" {
  # count         = 1
  ami               = data.aws_ami.server_ami.id
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = aws_key_pair.mtc_auth.id
  vpc_security_group_ids = [
    aws_security_group.emoji_app_public_sg.id
  ]
  subnet_id                   = aws_subnet.emoji_app_subnet-1a.id
  associate_public_ip_address = true
  user_data                   = data.cloudinit_config.user_data_lb.rendered

  root_block_device {
    volume_size = 8
  }

  provisioner "local-exec" {
    command = templatefile("ssh-config.tpl.sh", {
      host         = self.tags.Name
      ip           = self.public_ip
      user         = "ubuntu"
      identityfile = "~/.ssh/mtc-key"
    })

    interpreter = ["bash", "-c"]
  }

  tags = {
    Name = "${var.app-name}-lb"
  }
}

resource "aws_instance" "emoji_app" {
  count             = 2
  ami               = data.aws_ami.server_ami.id
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"

  vpc_security_group_ids = [
    aws_default_security_group.default.id,
  ]

  subnet_id                   = aws_subnet.emoji_app_subnet-1a.id
  associate_public_ip_address = true
  user_data                   = data.cloudinit_config.user_data_app.rendered

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "${var.app-name}-${count.index}"
  }
}
