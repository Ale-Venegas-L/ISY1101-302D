variable "region" {
  type    = string
  default = "us-east-1"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  description = "Llaves para EC2"
  type        = string
}

variable "mysql_root_password" {
  description = "contraseña para MySQL"
  type        = string
  sensitive   = true
}

variable "mysql_database" {
  type    = string
  default = "appdb"
}
