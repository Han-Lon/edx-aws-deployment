#####################################
## S3 Setup and Config File Upload ##
#####################################
# Set up an S3 bucket for holding the basic config/installation files
module "edx-config-bucket" {
  source = "registry.terraform.io/terraform-aws-modules/s3-bucket/aws"

  bucket = "edx-config-${var.environment}-${data.aws_caller_identity.current_account.account_id}-bucket"
  acl    = "private"

}

# Format the config.yml file with the environment_url
resource "local_file" "config-file-formatted" {
  filename = "formatted-config.yml"
  content = templatefile("./config.yml", {
    url = var.environment_url
  })
}

# Upload the above config.yml file to the config S3 bucket
resource "aws_s3_object" "config-file-upload" {
  bucket = module.edx-config-bucket.s3_bucket_id
  key    = "config.yml"
  source = local_file.config-file-formatted.filename


  etag = filemd5("./config.yml")
}

# Upload the Open edX Expect script
resource "aws_s3_object" "edx-installation-upload" {
  bucket = module.edx-config-bucket.s3_bucket_id
  key    = "install-and-quickstart-edx.exp"
  source = "./install-and-quickstart-edx.exp"

  etag = filemd5("./install-and-quickstart-edx.exp")
}

#####################
## S3 Access Setup ##
#####################

# Set up an S3 read policy so the app server can pull config from S3
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