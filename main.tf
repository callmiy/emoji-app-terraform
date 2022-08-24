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
  # region = "us-east-1"

  # shared_credentials_files = [
  #   "~/.aws/credentials"
  # ]

  # profile = "default"
}

# provider "docker" {}

# -----------------------------------------------------------------------------
# END PROVIDERS
# -----------------------------------------------------------------------------

# resource "aws_vpc" "emoji_app_vpc" {
#   cidr_block           = var.vpc_cidr
#   enable_dns_support   = true
#   enable_dns_hostnames = true
#
#   tags = {
#     Name = "${var.app_name}_vpc"
#   }
# }

# resource "aws_subnet" "emoji_app_subnet-1a" {
#   vpc_id                  = data.aws_vpc.emoji_app_vpc.id
#   cidr_block              = var.vpc_cidr
#   map_public_ip_on_launch = true
#   # availability_zone       = "us-east-1a"
#
#   tags = {
#     Name = "${var.app_name}-public-subnet"
#   }
# }



# resource "aws_internet_gateway" "emoji_app_internet_gateway" {
#   vpc_id = data.aws_vpc.emoji_app_vpc.id
#
#   tags = {
#     Name = "${var.app_name}-igw"
#   }
# }

resource "aws_route_table" "emoji_app_public_rt" {
  # vpc_id = aws_vpc.emoji_app_vpc.id
  vpc_id = data.aws_vpc.emoji_app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id = aws_internet_gateway.emoji_app_internet_gateway.id
    gateway_id = var.default_igw
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

resource "aws_route_table_association" "emoji_app_public_rt_assoc" {
  # subnet_id      = aws_subnet.emoji_app_subnet-1a.id
  subnet_id      = var.default_subnet_id
  route_table_id = aws_route_table.emoji_app_public_rt.id
}

# The aws default security group created for every vpc - this entry puts it
# under mnagement of terraform. By default, inbound traffic is only allowed
# from machines attached to this security group (denoted by `self = true`). We
# now modify this ingress rule to let in traffic from any machine within the
# VPC
resource "aws_default_security_group" "default" {
  # vpc_id = aws_vpc.emoji_app_vpc.id
  vpc_id = data.aws_vpc.emoji_app_vpc.id

  ingress {
    protocol = -1
    # This security group is the source of inbound traffic
    self      = true
    from_port = 0
    to_port   = 0

    # There is no cidr_blocks entry in the default config. We put it here
    # because we need to modify the default config
    # cidr_blocks = [
    #   var.vpc_cidr
    # ]
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
  name        = "${var.app_name}-public-sg"
  description = "${var.app_name} public security group"
  # vpc_id      = aws_vpc.emoji_app_vpc.id
  vpc_id = data.aws_vpc.emoji_app_vpc.id

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
    Name = "${var.app_name}-public-sg"
  }
}

resource "aws_key_pair" "mtc_auth" {
  key_name   = "mtckey"
  public_key = local.ssh_key
}

resource "aws_instance" "emoji_app-lb" {
  # count         = 1
  ami           = data.aws_ami.server_ami.id

  instance_type = "t2.micro"

  # availability_zone = "us-east-1a"

  key_name = aws_key_pair.mtc_auth.id

  vpc_security_group_ids = [
    aws_security_group.emoji_app_public_sg.id,
    aws_default_security_group.default.id,
  ]

  # subnet_id                   = aws_subnet.emoji_app_subnet-1a.id
  subnet_id                   = var.default_subnet_id

  associate_public_ip_address = true

  user_data                   = data.cloudinit_config.user_data_lb.rendered

  root_block_device {
    volume_size = 8
  }

  # provisioner "local-exec" {
  #   command = templatefile("ssh-config.tpl.sh", {
  #     host         = self.tags.Name
  #     ip           = self.public_ip
  #     user         = "ubuntu"
  #     identityfile = "~/.ssh/mtc-key"
  #   })
  #
  #   interpreter = ["bash", "-c"]
  # }

  tags = {
    Name = "${var.app_name}-lb"
  }
}

resource "aws_instance" "emoji_app" {
  count = 2
  ami   = data.aws_ami.server_ami.id

  instance_type = "t2.micro"
  # availability_zone = "us-east-1a"
  # key_name = aws_key_pair.mtc_auth.id

  vpc_security_group_ids = [
    # aws_security_group.emoji_app_public_sg.id,
    aws_default_security_group.default.id,
  ]

  # subnet_id                   = aws_subnet.emoji_app_subnet-1a.id
  subnet_id = var.default_subnet_id

  # Without `associate_public_ip_address = true`, machines on same
  # vpc subnet can not access http traffic ???
  associate_public_ip_address = true

  user_data = data.cloudinit_config.user_data_app.rendered

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "${var.app_name}-${count.index}"
  }
}
