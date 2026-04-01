provider "aws" {
  region = var.region
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "front" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.pub.id
  key_name                    = var.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pub_sg.id]

  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable --now docker
    usermod -a -G docker ec2-user

    docker pull nginx:stable
    mkdir -p /etc/nginx/conf.d

    cat > /etc/nginx/conf.d/backend.conf <<NGINX
    server {
      listen 80;
      location / {
        proxy_pass http://${aws_instance.back.private_ip}:8080;
      }
    }
    NGINX

    docker run -d --name nginx-proxy \
      -p 80:80 \
      -v /etc/nginx/conf.d:/etc/nginx/conf.d:ro \
      nginx:stable
  EOT

  tags = {
    Name = "ec2-front"
    Role = "front"
  }
}

resource "aws_instance" "back" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.priv.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.back_sg.id]

  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable --now docker
    usermod -a -G docker ec2-user

    docker run -d --name app \
      -p 8080:8080 \
      hashicorp/http-echo -text="Hello from back service"
  EOT

  tags = {
    Name = "ec2-back"
    Role = "back"
  }
}

resource "aws_instance" "data" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.priv.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable --now docker
    usermod -a -G docker ec2-user

    docker pull mysql:8
    docker run -d --name mysql-db \
      -e MYSQL_ROOT_PASSWORD=${var.mysql_root_password} \
      -e MYSQL_DATABASE=${var.mysql_database} \
      -p 3306:3306 \
      mysql:8 \
      --default-authentication-plugin=mysql_native_password
  EOT

  tags = {
    Name = "ec2-data"
    Role = "data"
  }
}

output "front_public_ip" {
  value = aws_instance.front.public_ip
}

output "back_private_ip" {
  value = aws_instance.back.private_ip
}

output "db_private_ip" {
  value = aws_instance.data.private_ip
}
