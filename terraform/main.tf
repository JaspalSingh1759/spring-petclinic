provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# Security Group
# ----------------------------
resource "aws_security_group" "petclinic_sg" {
  name        = "petclinic-sg"
  description = "Allow SSH and Petclinic access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Petclinic App"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# EC2 Instance (Ubuntu)
# ----------------------------
resource "aws_instance" "petclinic_ec2" {
  ami           = "ami-04a81a99f5ec58529" # Ubuntu 22.04 LTS in us-east-1
  instance_type = "t2.micro"
  key_name      = var.key_name
  security_groups = [aws_security_group.petclinic_sg.name]

  user_data = <<-EOF
    #!/bin/bash

    apt-get update -y

    # install Docker
    apt-get install -y ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io

    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker

    # install docker-compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # create app directory
    mkdir -p /app
  EOF

  tags = {
    Name = "petclinic-ubuntu-ec2"
  }
}

# ----------------------------
# Upload docker-compose.yml
# ----------------------------
resource "null_resource" "upload_compose" {
  depends_on = [aws_instance.petclinic_ec2]

  provisioner "file" {
    source      = "docker-compose.yml"
    destination = "/app/docker-compose.yml"

    connection {
      type        = "ssh"
      host        = aws_instance.petclinic_ec2.public_ip
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "cd /app",
      "docker-compose pull",
      "docker-compose up -d"
    ]

    connection {
      type        = "ssh"
      host        = aws_instance.petclinic_ec2.public_ip
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
  }
}

output "public_ip" {
  value = aws_instance.petclinic_ec2.public_ip
}

