# Terraform backend config -- if you want to use another backend instead of Terraform Cloud, set it here
terraform {
  cloud {
    organization = "redbell-eng"

    workspaces {
      name = "edx-aws-deployment"
    }
  }
}