# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-10
#
# The catalog every schema lives in, whether to create it, the groups
# that load, build and read, and the SQL warehouse dbt and dlt connect
# through.

variable "catalog" {
  description = "The Unity Catalog catalog; config/config.toml's [databricks] catalog."
  type        = string
  default     = "kds"
}

variable "create_catalog" {
  description = "Whether to create the catalog; false to use one that exists, such as workspace."
  type        = bool
  default     = true
}

variable "groups" {
  description = "Account groups to load, build and read, made first in the workspace's settings."
  type = object({
    loaders  = string
    builders = string
    readers  = string
  })
  default = {
    loaders  = "data-loaders"
    builders = "data-builders"
    readers  = "data-readers"
  }

  validation {
    condition     = length(distinct(values(tomap(var.groups)))) == 3
    error_message = "Name three different groups: one to load, one to build, one to read."
  }
}

variable "sql_warehouse_name" {
  description = "The SQL warehouse to connect through; the Free Edition starts with one."
  type        = string
  default     = "Serverless Starter Warehouse"
}
