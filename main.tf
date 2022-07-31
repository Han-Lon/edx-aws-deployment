# Dynamically grab the most recent AWS AL2 AMI
data "aws_ami" "al2-ami" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current_account" {}

module "edx-vpc" {
  source = "registry.terraform.io/terraform-aws-modules/vpc/aws"

  name = "edx-${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # TODO you'd change this to false for prod

  tags = {
    Terraform_Managed = "true"
    Environment       = var.environment
    Project           = "Open-edX"
  }
}

module "edx-config-bucket" {
  source = "registry.terraform.io/terraform-aws-modules/s3-bucket/aws"

  bucket = "edx-config-${var.environment}-${data.aws_caller_identity.current_account.account_id}-bucket"
  acl    = "private"

}

resource "local_file" "config-file-formatted" {
  filename = "formatted-config.yml"
  content = templatefile("./config.yml", {
    url = var.environment_url
  })
}

resource "aws_s3_object" "config-file-upload" {
  bucket = module.edx-config-bucket.s3_bucket_id
  key    = "config.yml"
  source = local_file.config-file-formatted.filename


  etag = filemd5("./config.yml")
}

resource "aws_s3_object" "ansible-playbook-upload" {
  bucket = module.edx-config-bucket.s3_bucket_id
  key = "install-and-start-edx.yaml"
  source = "./install-and-start-edx.yaml"

  etag = filemd5("./install-and-start-edx.yaml")
}

data "aws_iam_policy_document" "s3-read-policy" {
  statement {
    sid       = "S3GetObjects"
    actions   = ["s3:GetObject", "s3:GetObjectAcl"]
    resources = ["${module.edx-config-bucket.s3_bucket_arn}/*"]
  }
}

module "s3_access_policy" {
  source = "registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-policy"

  name        = "edx-get-object-${var.environment}-policy"
  path        = "/"
  description = "Allow getting objects from the edx config bucket"

  policy = data.aws_iam_policy_document.s3-read-policy.json
}

module "s3_access_role" {
  source = "registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  trusted_role_services = [
    "ec2.amazonaws.com"
  ]

  create_role             = true
  create_instance_profile = true
  role_requires_mfa       = false

  role_name = "edx-server-${var.environment}-role"
  custom_role_policy_arns = [
    module.s3_access_policy.arn,
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  ]
}

resource "aws_security_group" "edx-security-group" {
  name        = "edx-server-${var.environment}-sg"
  vpc_id      = module.edx-vpc.vpc_id
  description = "Allow inbound access to the edX server"

  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  ingress {
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["${var.allowed-ip}/32"]
  }

  egress {
    from_port        = 0
    protocol         = "-1"
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform_Managed = "true"
    Environment       = var.environment
    Project           = "Open-edX"
  }
}

# Spot instance request for the edX spot instance
# You probably wouldn't want to use a spot instance for production!!!
resource "aws_spot_instance_request" "edx-spot-instance" {
  ami           = data.aws_ami.al2-ami.image_id
  instance_type = "m5a.large"
  key_name      = var.ec2_key_name

  wait_for_fulfillment = true  # Needed or else tagging resources below will fail

  spot_type = "one-time"

  # TODO change both of these when converting to ALB architecture
  subnet_id                   = module.edx-vpc.public_subnets[0]
  associate_public_ip_address = true

  security_groups = [aws_security_group.edx-security-group.id]

  iam_instance_profile = module.s3_access_role.iam_instance_profile_name

  root_block_device {
    volume_size = 25 # Recommended MIN volume size per Open edX docs
  }

  tags = {
    Environment = var.environment
    Project     = "Open-edX"
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

mkdir -p /home/ec2-user/.local/share/tutor/
aws s3 cp s3://${aws_s3_object.config-file-upload.bucket}/${aws_s3_object.config-file-upload.key} /home/ec2-user/.local/share/tutor/config.yml

EOF
}

data "aws_ssm_document" "launch-tutor-doc" {
  name            = "AWS-ApplyAnsiblePlaybooks"
  document_format = "YAML"
}

resource "aws_ssm_association" "launch-tutor-task" {
  depends_on = [aws_spot_instance_request.edx-spot-instance, aws_ec2_tag.edx-server-tagging]
  name             = data.aws_ssm_document.launch-tutor-doc.name

  targets {
    key    = "tag:Project"
    values = ["Open-edX"]
  }

  parameters = {
    SourceType = ["S3"]
    SourceInfo = jsonencode({"path": "s3://${aws_s3_object.ansible-playbook-upload.bucket}/${aws_s3_object.ansible-playbook-upload.key}"})
    InstallDependencies = ["True"]
  }

  wait_for_success_timeout_seconds = 1800

}

locals {
  server_tags = {"Project": "Open-edX", "Name": "Open-edX-server"}
}

# Needed because the spot request resource in Terraform doesn't apply tags to the instance that's created, just the spot request itself
# https://github.com/hashicorp/terraform/issues/3263
resource "aws_ec2_tag" "edx-server-tagging" {
  for_each = local.server_tags
  key         = each.key
  resource_id = aws_spot_instance_request.edx-spot-instance.spot_instance_id
  value       = each.value
}