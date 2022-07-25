# Dynamically grab the most recent AWS AL2 AMI
data "aws_ami" "al2-ami" {
  owners = ["amazon"]
  most_recent = true

  filter {
    name = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current_account" {}

module "edx-vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "edx-${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true  # TODO you'd change this to false for prod

  tags = {
    Terraform_Managed = "true"
    Environment = var.environment
    Project = "Open-edX"
  }
}

module "edx-config-bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "edx-config-${var.environment}-${data.aws_caller_identity.current_account.account_id}-bucket"
  acl = "private"

}

resource "aws_s3_bucket_object" "config-file-upload" {
  bucket = module.edx-config-bucket.s3_bucket_id
  key = "config.yaml"
  source = "./config.yaml"

  etag = filemd5("./config.yaml")
}

data "aws_iam_policy_document" "s3-read-policy" {
  statement {
    sid = "S3GetObjects"
    actions = ["s3:GetObject", "s3:GetObjectAcl"]
    resources = ["${module.edx-config-bucket.s3_bucket_arn}/*"]
  }
}

module "s3_access_policy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name = "edx-get-object-${var.environment}-policy"
  path = "/"
  description = "Allow getting objects from the edx config bucket"

  policy = data.aws_iam_policy_document.s3-read-policy.json
}

module "s3_access_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  trusted_role_services = [
    "ec2.amazonaws.com"
  ]

  create_role = true
  create_instance_profile = true

  role_name = "edx-server-${var.environment}-role"
  custom_role_policy_arns = [
    module.s3_access_policy.arn
  ]
}

resource "aws_security_group" "edx-security-group" {
  name = "edx-server-${var.environment}-sg"
  vpc_id = module.edx-vpc.vpc_id
  description = "Allow inbound access to the edX server"

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  ingress {
    from_port = 443
    protocol = "tcp"
    to_port = 443
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform_Managed = "true"
    Environment = var.environment
    Project = "Open-edX"
  }
}

# Spot instance request for the edX spot instance
# You probably wouldn't want to use a spot instance for production!!!
resource "aws_spot_instance_request" "edx-spot-instance" {
  ami = data.aws_ami.al2-ami.image_id
  instance_type = "m5a.large"
  key_name = var.ec2_key_name

  spot_type = "one-time"

  # TODO change both of these when converting to ALB architecture
  subnet_id = module.edx-vpc.public_subnets[0]
  associate_public_ip_address = true

  security_groups = [aws_security_group.edx-security-group.id]

  iam_instance_profile = module.s3_access_role.iam_instance_profile_arn

  root_block_device {
    volume_size = 25  # Recommended MIN volume size per Open edX docs
  }

  user_data = <<EOF
#!/bin/bash
yum update -y

yum install docker python3-pip gcc python3-devel -y
yes | pip3 install docker-compose
systemctl enable docker.service
systemctl start docker.service

usermod -a -G docker ec2-user

pip3 install "tutor[full]"

aws s3 cp s3://${aws_s3_bucket_object.config-file-upload.bucket}/${aws_s3_bucket_object.config-file-upload.key} ./config.yml
EOF
}