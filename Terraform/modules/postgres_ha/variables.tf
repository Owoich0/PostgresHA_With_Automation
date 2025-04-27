variable "key_name" {
  description = "Name of the SSH key pair to use"
  type        = string
}

variable "ami" {
  description = "AMI to use for EC2 instances"
  type        = string
  default     = "ami-0a73e96a849c232cc"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "data_volume_size" {
  description = "Size of the EBS volume for PostgreSQL data"
  type        = number
  default     = 50
}

variable "wal_volume_size" {
  description = "Size of the EBS volume for WAL"
  type        = number
  default     = 20
}

variable "instance_count" {
  description = "Count of instances"
  type        = number
  default     = 3
}