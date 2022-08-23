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
      ssh_key                        = local.ssh_key
      DOCKER_PASSWORD                = var.DOCKER_PASSWORD
      app_docker_published_http_port = var.app_docker_published_http_port
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

data "aws_vpc" "emoji_app_vpc" {
  default = true
}
