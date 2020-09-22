# AWS infrastructure resources
data "aws_availability_zones" "available" {
}

resource "tls_private_key" "global_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_private_key_pem" {
  filename          = "${path.cwd}/.output/id_rsa"
  sensitive_content = tls_private_key.global_key.private_key_pem
  file_permission   = "0600"
}

resource "local_file" "ssh_public_key_openssh" {
  filename = "${path.cwd}/.output/id_rsa.pub"
  content  = tls_private_key.global_key.public_key_openssh
}

# Temporary key pair used for SSH accesss
resource "aws_key_pair" "rke_key_pair" {
  key_name_prefix = "${var.prefix}-rancher-"
  public_key      = tls_private_key.global_key.public_key_openssh
}

# Security group to allow all traffic
resource "aws_security_group" "rancher_sg_allowall" {
  vpc_id = var.vpc_id

  name        = "${var.prefix}-rancher-allowall"
  description = "Rancher quickstart - allow all traffic"

  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Creator = "rke"
    Name = "rke-rancher_sg_allowall"
  }
}

data "template_file" "init" {
  template = file("files/userdata.template")

  vars = {
    docker_version   = var.docker_version
    username         = local.node_username
  }
}


# AWS EC2 instance For RKE nodes
resource "aws_instance" "rancher_server" {
  count = 3

  subnet_id = element(var.private_subnet_ids, count.index)

  associate_public_ip_address = true

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  key_name        = aws_key_pair.rke_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.rancher_sg_allowall.id]

  user_data = data.template_file.init.rendered

  root_block_device {
    volume_size = 16
  }

  tags = {
    Name    = "${var.prefix}-rancher-server-${count.index}"
    Creator = "rancher"
  }
}

resource "aws_lb_target_group" "target-https" {
  name     = "rancher-tcp-443"
  port     = 443
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = var.vpc_id

  health_check {
    protocol = "HTTP"
    path = "/healthz"
    port = "80"
    healthy_threshold = 3
    unhealthy_threshold = 3
    timeout = 6
    interval = 10
  }

  tags = {
    Name = "rancher-tcp-443"
  }
}


resource "aws_lb_target_group" "target-http" {
  name     = "rancher-tcp-80"
  port     = 80
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = var.vpc_id

  health_check {
    protocol = "HTTP"
    path = "/healthz"
    port = "80"
    healthy_threshold = 3
    unhealthy_threshold = 3
    timeout = 6
    interval = 10
  }

  tags = {
    Name = "rancher-tcp-80"
  }
}

resource "aws_lb_target_group_attachment" "rancher-https" {
  count            = 3
  target_group_arn = aws_lb_target_group.target-https.arn
  target_id        = element(aws_instance.rancher_server.*.id, count.index)
  port             = 443
}

resource "aws_lb_target_group_attachment" "rancher-http" {
  count            = 3
  target_group_arn = aws_lb_target_group.target-http.arn
  target_id        = element(aws_instance.rancher_server.*.id, count.index)
  port             = 80
}

resource "aws_security_group" "nlb" {
  name = "rancher"
  description = "Security group for rancher nlb"
  vpc_id = var.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  tags = {
    "Name" = "rancher-nlb-sg"
  }
}

resource "aws_security_group_rule" "allow-http" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "TCP"
  security_group_id = aws_security_group.nlb.id
  cidr_blocks = [
    "0.0.0.0/0"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow-https" {
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "TCP"
  security_group_id = aws_security_group.nlb.id
  cidr_blocks = [
    "0.0.0.0/0"]

  lifecycle {
    create_before_destroy = true
  }
}
