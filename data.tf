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

# Used to refer to the current AWS account ID
data "aws_caller_identity" "current_account" {}