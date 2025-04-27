This project automates the deployment of a production-grade **PostgreSQL High Availability Cluster** on AWS. It leverages:


| Tool          | Purpose                             |
|---------------|-------------------------------------|
| Terraform     | Infrastructure provisioning (EC2, EBS) |
| Ansible       | Cluster configuration management    |
| PostgreSQL 14 | Database engine                     |
| Patroni       | PostgreSQL HA with etcd             |
| etcd          | Distributed DCS store for Patroni   |
| HAProxy       | Connection load balancer            |
| Keepalived    | Virtual IP failover (VRRP)          |
| pgBackRest    | Backups & WAL archiving             |
| AWS S3        | Backup storage                      |
| Monitoring    | Prometheus and Grafana              |