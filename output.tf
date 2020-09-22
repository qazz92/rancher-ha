output "rancher_node_ip" {
  value = aws_instance.rancher_server[0].public_ip
}
