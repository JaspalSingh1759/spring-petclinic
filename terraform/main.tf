provider "aws" {
  region = "us-east-1"
}
resource "aws_iam_role" "ec2_rexray" {
  name = "ec2-rexray-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2-rexray-policy"
  role = aws_iam_role.ec2_rexray.id
  policy = data.aws_iam_policy_document.ec2_policy.json
}

data "aws_iam_policy_document" "ec2_policy" {
  statement {
    actions = [
      "ec2:CreateVolume","ec2:AttachVolume","ec2:DetachVolume","ec2:DeleteVolume",
      "ec2:CreateSnapshot","ec2:DescribeVolumes","ec2:DescribeInstances","ec2:ModifyVolume",
      "ec2:DescribeSnapshots","ec2:CreateTags","ec2:DescribeTags"
    ]
    resources = ["*"]
  }
  statement {
    actions = ["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "ebs_key" {
  description = "KMS key for encrypted EBS volumes in demo"
  deletion_window_in_days = 7
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"Enable IAM",
      "Effect":"Allow",
      "Principal":{"AWS":"*"},
      "Action":"kms:*",
      "Resource":"*"
    }
  ]
}
POLICY
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
  #security_groups = [aws_security_group.petclinic_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.petclinic_sg.name]

user_data = <<-EOF
#!/bin/bash
set -ex

### =======================
### Cloud-init Logging
### =======================
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "=== User-data started at \$(date) ==="

### =======================
### 1. System Prep
### =======================
apt-get update -y
apt-get install -y \
  ca-certificates curl gnupg lsb-release jq awscli \
  gnupg2 software-properties-common

### =======================
### 2. Install Docker
### =======================
mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
 https://download.docker.com/linux/ubuntu \
 \$(lsb_release -cs) stable" \
 > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

### Wait for Docker
echo "Waiting for Docker daemon..."
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    echo "Docker is ready."
    break
  fi
  echo "Docker not ready yet... retrying (\$i/30)"
  sleep 2
done

### =======================
### 3. Install REX-Ray (EBS)
### =======================
echo "Installing REX-Ray..."
REXRAY_VERSION="0.12.1"

curl -sSL https://github.com/rexray/rexray/releases/download/v0.12.1/rexray_0.12.1_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin

chmod +x /usr/local/bin/rexray

### =======================
### 4. Create REX-Ray config
### =======================
mkdir -p /etc/rexray

# Safe region lookup for ALL Ubuntu AMIs
AWS_REGION=\$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.\$//')

cat <<'EOF_RR' > /etc/rexray/config.yml
libstorage:
  service: ebs

ebs:
  accessKey: ""        # IAM role auto-auth
  secretKey: ""        # IAM role auto-auth
  region: REPLACE_REGION
EOF_RR

# Replace placeholder with detected region
sed -i "s/REPLACE_REGION/\$AWS_REGION/" /etc/rexray/config.yml

### =======================
### 5. REX-Ray systemd service
### =======================
cat <<'EOF_SYS' > /etc/systemd/system/rexray.service
[Unit]
Description=REX-Ray Storage Orchestration Engine
After=docker.service
Wants=docker.service

[Service]
ExecStart=/usr/local/bin/rexray start -f
ExecStop=/usr/local/bin/rexray stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SYS

systemctl daemon-reload
systemctl enable rexray
systemctl start rexray

sleep 5
rexray volume ls || echo "REX-Ray still initializing..."

### =======================
### 6. Application Setup
### =======================
mkdir -p /app
cd /app

cat <<'EOF_DC' > docker-compose.yml
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
      - pgdata:/var/lib/postgresql/data   # <-- EBS volume via REX-Ray

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
  pgdata:
    driver: rexray/ebs
EOF_DC

### =======================
### 7. Start Application
### =======================
docker compose pull
docker compose up -d

echo "=== User-data completed successfully at \$(date) ==="
EOF


  tags = {
    Name = "petclinic-ubuntu-ec2"
  }
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-rexray-profile"
  role = aws_iam_role.ec2_rexray.name
}

output "public_ip" {
  value = aws_instance.petclinic_ec2.public_ip
}
