#############################################
## VPC and Security Group Networking Setup ##
#############################################

# Stand up a new VPC specifically for the Open edX environment
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

# Set up a security group for the Open edX app server
resource "aws_security_group" "edx-security-group" {
  name        = "edx-server-${var.environment}-sg"
  vpc_id      = module.edx-vpc.vpc_id
  description = "Allow inbound access to the edX server"

  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Extra ports needed for Open edX APIs and subsystems
  ingress {
    from_port   = 18000
    protocol    = "tcp"
    to_port     = 18999
    cidr_blocks = ["0.0.0.0/0"]
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

#########################################################
## App Server Setup (Using EC2 Spot Instance Requests) ##
#########################################################

# Spot instance request for the edX spot instance
# You probably wouldn't want to use a spot instance for production!!!
resource "aws_spot_instance_request" "edx-spot-instance" {
  ami           = data.aws_ami.al2-ami.image_id
  instance_type = "m5a.large"
  key_name      = var.ec2_key_name

  wait_for_fulfillment = true # Needed or else tagging resources below will fail

  spot_type = "one-time"

  subnet_id                   = module.edx-vpc.public_subnets[0]
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.edx-security-group.id]

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

amazon-linux-extras install epel -y

# Install dependencies, run docker
yum install docker python3-pip gcc python3-devel haveged expect -y
systemctl enable docker.service
systemctl start docker.service

# Allow non-root ec2-user to run docker commands
usermod -a -G docker ec2-user

# docker-compose gets installed to /usr/local/bin, which is not in root's PATH by default
echo "export PATH=/usr/local/bin:$PATH" >> ~/.bashrc

# Install docker-compose from source
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install the Tutor utility for isntalling Open edX
pip3 install "tutor[full]"

# Copy config files from S3 to relevant path locally, set up file ownership
mkdir -p /home/ec2-user/.local/share/tutor/
aws s3 cp s3://${aws_s3_object.config-file-upload.bucket}/${aws_s3_object.config-file-upload.key} /home/ec2-user/.local/share/tutor/config.yml
chown -R ec2-user:ec2-user /home/ec2-user/.local/share/tutor/

aws s3 cp s3://${aws_s3_object.config-file-upload.bucket}/${aws_s3_object.edx-installation-upload.key} /home/ec2-user/install-and-quickstart-edx.exp
chown ec2-user:ec2-user /home/ec2-user/install-and-quickstart-edx.exp
chmod 740 /home/ec2-user/install-and-quickstart-edx.exp

chmod 666 /var/run/docker.sock
EOF
}

# Needed because the spot request resource in Terraform doesn't apply tags to the instance that's created, just the spot request itself
# https://github.com/hashicorp/terraform/issues/3263
resource "aws_ec2_tag" "edx-server-tagging" {
  for_each    = local.server_tags
  key         = each.key
  resource_id = aws_spot_instance_request.edx-spot-instance.spot_instance_id
  value       = each.value
}