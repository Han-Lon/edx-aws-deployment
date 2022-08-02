variable "environment" {
  description = "The respective environment for this deployment. Pick dev, test, or prod"
  type        = string

  validation {
    condition     = can(regex("dev|test|prod", var.environment))
    error_message = "Invalid environment provided."
  }
}

variable "allowed-ip" {
  description = "The allowed IP address for inbound SSH, HTTP, and HTTPS traffic. This would need to be changed for a true prod deployment, unless all students are using a preset IP (e.g. with a VPN)"
  type        = string
}

variable "ec2_key_name" {
  description = "Name of the EC2 key pair to be used for securing access to the instance."
}

variable "environment_url" {
  description = "The URL that the instance(s) will be reachable at. e.g. edu.example.com"
}

variable "lb_certificate_arn" {
  description = "ARN of the AWS ACM certificate generated for the load balancer. The certificates must be for the same domain as the environment_url value"
}