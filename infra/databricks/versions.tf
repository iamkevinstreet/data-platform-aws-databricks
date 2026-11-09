# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# Terraform and the Databricks provider this root needs. The provider
# reads DATABRICKS_HOST and DATABRICKS_TOKEN from the environment, and
# uses workspace-level APIs only: the Free Edition has no account APIs.

terraform {
  required_version = ">= 1.10"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.70, < 2.0"
    }
  }

  backend "s3" {}
}

provider "databricks" {}
