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
  ami           = "ami-04a81a99f5ec58529"
  instance_type = "t2.micro"
  key_name      = var.key_name
  security_groups = [aws_security_group.petclinic_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y

    # Install dependencies for Docker repo
    apt-get install -y ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    # Install Docker & Docker Compose plugin
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add ubuntu user to docker group
    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker

    # Create app directory
    mkdir -p /app
    cd /app

    # Write docker-compose.yml
    cat <<'EOC' > docker-compose.yml
    version: "3.8"

    services:
      db:
        image: postgres:15
        environment:
          POSTGRES_DB: petclinic
          POSTGRES_USER: petuser
          POSTGRES_PASSWORD: petpass
        ports:
          - "5432:5432"
        volumes:
          - dbdata:/var/lib/postgresql/data

      app:
        image: jaspsing369/petclinic:latest
        environment:
          SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/petclinic
          SPRING_DATASOURCE_USERNAME: petuser
          SPRING_DATASOURCE_PASSWORD: petpass
        ports:
          - "8080:8080"
        depends_on:
          - db

    volumes:
      dbdata:
    EOC

    # Start the application
    docker compose up -d
  EOF

  tags = {
    Name = "petclinic-ubuntu-ec2"
  }
}

output "public_ip" {
  value = aws_instance.petclinic_ec2.public_ip
}
