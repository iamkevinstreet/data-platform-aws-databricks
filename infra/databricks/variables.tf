# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# The catalog every schema lives in, whether to create it, and the SQL
# warehouse dbt and dlt connect through.

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

variable "sql_warehouse_name" {
  description = "The SQL warehouse to connect through; the Free Edition starts with one."
  type        = string
  default     = "Serverless Starter Warehouse"
}
