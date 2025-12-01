terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure via -backend-config or fill in bucket/key/region before terraform init.
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = local.default_tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Use two AZs by default
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  default_tags = merge({
    Environment = var.environment
    Project     = "SBW-ClickStream"
    ManagedBy   = "Terraform"
  }, var.extra_tags)
}
