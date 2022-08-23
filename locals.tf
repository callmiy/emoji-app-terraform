locals {
  nginx_conf_text = base64encode(templatefile("./nginx.tpl.conf", {
    instance0 = "${aws_instance.emoji_app[0].private_ip}${var.app_docker_published_http_port == "80" ? "" : ":${var.app_docker_published_http_port}"}"

    instance1 = "${aws_instance.emoji_app[1].private_ip}${var.app_docker_published_http_port == "80" ? "" : ":${var.app_docker_published_http_port}"}"
  }))

  ssh_key = file("~/.ssh/mtc-key.pub")
}
