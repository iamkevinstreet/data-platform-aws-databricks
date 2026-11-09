# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# Terraform and the AWS provider this root needs. State lives in S3 with
# S3's own lock file (Terraform 1.10 and later); the bucket and key come
# from a backend file at init, so none is written here:
#   terraform init -backend-config=backend.hcl

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}
