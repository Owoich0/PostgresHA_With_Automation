data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  my_public_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

resource "aws_key_pair" "deployer" {
  key_name   = "ha-postgres-key"
  public_key = file("~/.ssh/ha-postgres-key.pub")
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "postgres_sg" {
  name        = "postgres-ha-sg"
  description = "Allow PostgreSQL, Patroni, etcd, SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [local.my_public_ip_cidr]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [local.my_public_ip_cidr]
  }
  ingress {
    from_port   = 9187
    to_port     = 9187
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "postgres_nodes" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
  }

  ebs_block_device {
    device_name = "/dev/xvdf"
    volume_size = var.data_volume_size
    volume_type = "gp3"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name = "/dev/xvdg"
    volume_size = var.wal_volume_size
    volume_type = "gp3"
    delete_on_termination = true
  }



  /* user_data = <<-EOF
              #!/bin/bash
              set -e

              # Format and mount WAL volume
              if [ -b /dev/nvme1n1 ]; then
                if ! mountpoint -q /var/lib/pgsql/wal; then
                  sudo mkfs.ext4 -F /dev/nvme1n1
                  sudo mkdir -p /var/lib/pgsql/wal
                  echo "/dev/nvme1n1 /var/lib/pgsql/wal ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
                  sudo mount /var/lib/pgsql/wal
                fi
              fi

              # Format and mount DATA volume
              if [ -b /dev/nvme2n1 ]; then
                if ! mountpoint -q /var/lib/pgsql/data; then
                  sudo mkfs.ext4 -F /dev/nvme2n1
                  sudo mkdir -p /var/lib/pgsql/data
                  echo "/dev/nvme2n1 /var/lib/pgsql/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
                  sudo mount /var/lib/pgsql/data
                fi
              fi

              # Reload systemd to pick up fstab changes
              sudo systemctl daemon-reexec
              sudo systemctl daemon-reload

              EOF
 */
  tags = {
    Name = "postgres-node-${count.index + 1}"
  }
}


resource "null_resource" "wait_for_instance" {
  depends_on = [aws_instance.postgres_nodes]

  provisioner "local-exec" {
    command = "echo 'Waiting 300 seconds for EC2 init...'; sleep 300"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "mount_disks" {
  count = 3

  depends_on = [
    null_resource.wait_for_instance
  ]

  connection {
    type        = "ssh"
    user        = "rocky"
    private_key = file("~/.ssh/ha-postgres-key")
    host        = aws_instance.postgres_nodes[count.index].public_ip
  }

  provisioner "remote-exec" {
  inline = [
    "sudo bash -c '",

    # Format disks if not formatted
    "  mkfs.ext4 -F /dev/nvme1n1 || true;",
    "  mkfs.ext4 -F /dev/nvme2n1 || true;",

    # Create mount directories
    "  mkdir -p /var/lib/pgsql/wal /var/lib/pgsql/data;",

    # Update fstab if needed
    "  grep -q nvme1n1 /etc/fstab || echo \"/dev/nvme1n1 /var/lib/pgsql/wal ext4 defaults,nofail 0 2\" >> /etc/fstab;",
    "  grep -q nvme2n1 /etc/fstab || echo \"/dev/nvme2n1 /var/lib/pgsql/data ext4 defaults,nofail 0 2\" >> /etc/fstab;",

    "  mount /var/lib/pgsql/wal || true;",
    "  mount /var/lib/pgsql/data || true;",
    "'"
  ]
  }
}


resource "local_file" "ansible_inventory" {
  depends_on = [aws_instance.postgres_nodes]

  content = templatefile("${path.module}/inventory.ini.tpl", {
    nodes = [
      for idx, instance in aws_instance.postgres_nodes : {
        name       = "postgres-node-${idx + 1}"
        public_ip  = instance.public_ip
        private_ip = instance.private_ip
      }
    ]
  })

  filename = "${path.root}/../ansible/inventory/inventory.ini"
}

resource "null_resource" "run_ansible" {
  depends_on = [local_file.ansible_inventory,null_resource.wait_for_instance,
    null_resource.mount_disks]

  provisioner "local-exec" {
    command = <<EOT
      sleep 60
      ANSIBLE_HOST_KEY_CHECKING=False \
      ansible-playbook -i ${path.root}/../ansible/inventory/inventory.ini \
                       ${path.root}/../ansible/site.yml
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}
