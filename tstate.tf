terraform {
  cloud {
    organization = "redbell-eng"

    workspaces {
      name = "edx-aws-deployment"
    }
  }
}