provider "aws" {
  region = "us-east-1"
}

# =========================================================
# IAM ROLE FOR EC2 (MINIMAL, CLEAN, NO REX-RAY)
# =========================================================
resource "aws_iam_role" "ec2_role" {
  name = "ec2-petclinic-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EC2 only needs permission for Describe* (not EBS Create/Delete)
resource "aws_iam_role_policy" "ec2_basic" {
  name = "ec2-basic-policy"
  role = aws_iam_role.ec2_role.id

  policy = data.aws_iam_policy_document.ec2_basic.json
}

data "aws_iam_policy_document" "ec2_basic" {
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "ec2:DescribeAvailabilityZones"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-petclinic-profile"
  role = aws_iam_role.ec2_role.name
}

# =========================================================
# SECURITY GROUP
# =========================================================
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

# =========================================================
# EBS VOLUME FOR POSTGRES (20GB)
# =========================================================
resource "aws_ebs_volume" "pgdata" {
  availability_zone = "us-east-1a"  
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "pgdata"
  }
}

# Attach EBS volume to EC2 (as /dev/sdf → mapped as /dev/nvme1n1)
resource "aws_volume_attachment" "pg_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.pgdata.id
  instance_id = aws_instance.petclinic_ec2.id
}

# =========================================================
# EC2 INSTANCE
# =========================================================
resource "aws_instance" "petclinic_ec2" {
  ami                         = "ami-04a81a99f5ec58529"
  instance_type               = "t2.micro"
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.petclinic_sg.id]
  availability_zone           = "us-east-1a"

  # ----------------------------
  # USER DATA (YOUR NEW SCRIPT)
  # ----------------------------
user_data = <<-EOF
#!/bin/bash
set -ex

### =======================
### Cloud-init Logging
### =======================
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "=== User-data started at $(date) ==="

### =======================
### 1. System Prep
### =======================
apt-get update -y
apt-get install -y \
  ca-certificates curl gnupg lsb-release jq \
  gnupg2 software-properties-common unzip

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

### =======================
### 2. Install Docker
### =======================
mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" \
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
  echo "Docker not ready yet... retrying ($i/30)"
  sleep 2
done

### =======================
### 3. Mount & Prepare EBS Volume
### =======================
echo "Preparing EBS volume..."

# Allow time for the disk to attach
sleep 10

DEVICE="/dev/nvme1n1"

# Validate device exists
if [ ! -b "$DEVICE" ]; then
  echo "ERROR: EBS volume not found at $DEVICE"
  lsblk
  exit 1
fi

# Format only if needed
if ! blkid $DEVICE; then
  echo "Formatting EBS volume as ext4..."
  mkfs.ext4 $DEVICE
fi

mkdir -p /data
mount $DEVICE /data

# Auto-mount on reboot
echo "$DEVICE /data ext4 defaults,nofail 0 2" >> /etc/fstab

# Permissions for Postgres
chown -R ubuntu:ubuntu /data
chmod 775 /data

### =======================
### 4. Application Setup (Docker Compose)
### =======================
mkdir -p /app
cd /app

cat <<EOF_DC > docker-compose.yml
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
      - /data:/var/lib/postgresql/data

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
EOF_DC

### =======================
### 5. Start Application
### =======================
docker compose pull
docker compose up -d

echo "=== User-data completed successfully at $(date) ==="
EOF

  tags = {
    Name = "petclinic-ubuntu-ec2"
  }
}

output "public_ip" {
  value = aws_instance.petclinic_ec2.public_ip
}
