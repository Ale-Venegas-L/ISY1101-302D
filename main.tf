provider "aws" {
  region = var.region
}

# Data source para obtener la AMI más reciente de Amazon Linux 2
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --- LAUNCH TEMPLATES (Requerimiento de Automatización IE5) ---

# Template para la capa Frontend
resource "aws_launch_template" "front_lt" {
  name_prefix   = "front-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    subnet_id                   = aws_subnet.pub.id
    associate_public_ip_address = true
    security_groups             = [aws_security_group.pub_sg.id]
  }

  user_data = base64encode(<<-EOT
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

    docker run -d --name nginx-proxy -p 80:80 -v /etc/nginx/conf.d:/etc/nginx/conf.d:ro nginx:stable
  EOT
  )
}

# Template para la capa Backend
resource "aws_launch_template" "back_lt" {
  name_prefix   = "back-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    subnet_id       = aws_subnet.priv.id
    security_groups = [aws_security_group.back_sg.id]
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable --now docker
    usermod -a -G docker ec2-user

    docker run -d --name app -p 8080:8080 hashicorp/http-echo -text="Hello from back service" -listen=:8080
  EOT
  )
}

# Template para la capa Data (Incluye Persistencia IE5)
resource "aws_launch_template" "data_lt" {
  name_prefix   = "data-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    subnet_id       = aws_subnet.priv.id
    security_groups = [aws_security_group.db_sg.id]
  }

  # Configuración de bloque para persistencia de datos
  block_device_mappings {
    device_name = "/dev/sdb"
    ebs {
      volume_size           = 10
      volume_type           = "gp2"
      delete_on_termination = false
    }
  }

  user_data = base64encode(<<-EOT
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
  )
}

# --- INSTANCIAS (Implementación Lift & Shift) ---

resource "aws_instance" "front" {
  launch_template {
    id      = aws_launch_template.front_lt.id
    version = "$Latest"
  }

  tags = {
    Name = "ec2-front"
    Role = "front"
  }
}

resource "aws_instance" "back" {
  launch_template {
    id      = aws_launch_template.back_lt.id
    version = "$Latest"
  }

  tags = {
    Name = "ec2-back"
    Role = "back"
  }
}

resource "aws_instance" "data" {
  launch_template {
    id      = aws_launch_template.data_lt.id
    version = "$Latest"
  }

  tags = {
    Name = "ec2-data"
    Role = "data"
  }
}

# --- ADMINISTRACIÓN Y SEGURIDAD (IE7, IE10) ---

# Usar un perfil de instancia existente en lugar de crear rol/perfil IAM en Terraform.

# --- OUTPUTS ---

output "front_public_ip" {
  value = aws_instance.front.public_ip
}

output "back_private_ip" {
  value = aws_instance.back.private_ip
}

output "db_private_ip" {
  value = aws_instance.data.private_ip
}
