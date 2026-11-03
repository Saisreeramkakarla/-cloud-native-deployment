
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "cloud-native-security-group"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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

# IAM Role for CloudWatch Agent
resource "aws_iam_role" "cloudwatch_role" {
  name = "cloud-native-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach CloudWatch permissions
resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "cloudwatch_profile" {
  name = "cloud-native-cloudwatch-profile"
  role = aws_iam_role.cloudwatch_role.name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/cloud-native/application"
  retention_in_days = 7
}

# SNS Topic
resource "aws_sns_topic" "alerts" {
  name = "cloud-native-alerts"
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "email_alert" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EC2 Instance
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cloudwatch_profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    apt-get update -y
    apt-get install -y docker.io wget

    systemctl enable docker
    systemctl start docker

    # Download CloudWatch Agent
    wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
      -O /tmp/amazon-cloudwatch-agent.deb

    dpkg -i /tmp/amazon-cloudwatch-agent.deb

    # CloudWatch Agent Configuration
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
    {
      "agent": {
        "metrics_collection_interval": 60
      },
      "metrics": {
        "namespace": "CloudNative/EC2",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent"]
          },
          "disk": {
            "measurement": ["used_percent"],
            "resources": ["/"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/syslog",
                "log_group_name": "/cloud-native/application",
                "log_stream_name": "syslog"
              },
              {
                "file_path": "/var/log/cloud-init-output.log",
                "log_group_name": "/cloud-native/application",
                "log_stream_name": "cloud-init"
              },
              {
                "file_path": "/var/lib/docker/containers/*/*.log",
                "log_group_name": "/cloud-native/application",
                "log_stream_name": "docker"
              }
            ]
          }
        }
      }
    }
    CWCONFIG

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

  EOF

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name        = "Cloud-Native-Application"
    Environment = "Development"
    Project     = "Automated-Deployment"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch_policy,
    aws_cloudwatch_log_group.app_logs
  ]
}
