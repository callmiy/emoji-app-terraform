variable "host_os" {
  type = string
  default = "linux"
}

variable "app_name" {
  type    = string
  default = "emoji_app"
}

variable "vpc_cidr" {
  type = string
  default = "172.31.0.0/16"
}

variable "DOCKER_PASSWORD" {
  type = string
}

variable "default_subnet_id" {
  type    = string
}

variable "default_igw" {
  type    = string
}

variable "app_docker_published_http_port" {
  type    = string
  default = "80"
}
