output "node_ips" {
  value = [
    for i, instance in aws_instance.postgres_nodes :
    {
      name       = "postgres-node-${i + 1}"
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
    }
  ]
}