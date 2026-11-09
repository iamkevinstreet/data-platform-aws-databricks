# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# Every Unity Catalog object the warehouse needs, so a deleted workspace
# is rebuilt from this repository: the catalog, one schema per layer, a
# landing volume for exported files, three groups and their grants.
# Loaders write the raw schemas only; builders read raw and own the
# models; readers see the published marts and nothing under them.

locals {
  raw_schemas = {
    raw_ai_ops = "AI operations: the apps' committed results, loaded by dlt at pinned commits."
    landing    = "Files dropped for loading, such as review exports."
  }
  model_schemas = {
    staging      = "dbt staging views: one per raw table."
    intermediate = "dbt views that line the apps' formats up."
    reference    = "dbt seeds: reference tables kept in the repository."
  }
  mart_schemas = {
    ai_ops = "The AI operations mart: runs, cases, calls, spans and costs."
  }
  schemas = merge(local.raw_schemas, local.model_schemas, local.mart_schemas)
  groups  = ["data-loaders", "data-builders", "data-readers"]
}

resource "databricks_catalog" "warehouse" {
  count   = var.create_catalog ? 1 : 0
  name    = var.catalog
  comment = "The data platform's warehouse, managed by Terraform."
}

resource "databricks_schema" "layer" {
  for_each     = local.schemas
  catalog_name = var.catalog
  name         = each.key
  comment      = each.value

  depends_on = [databricks_catalog.warehouse]
}

resource "databricks_volume" "exports" {
  name         = "exports"
  catalog_name = var.catalog
  schema_name  = databricks_schema.layer["landing"].name
  volume_type  = "MANAGED"
  comment      = "Review exports as JSON files, read by the loaders."
}

resource "databricks_group" "role" {
  for_each     = toset(local.groups)
  display_name = each.key
}

# Grants are authoritative: they replace every grant on the object. So the
# catalog's are set only on a catalog this root created, never on one that
# others share, such as the Free Edition's workspace catalog.
resource "databricks_grants" "catalog" {
  count   = var.create_catalog ? 1 : 0
  catalog = var.catalog

  dynamic "grant" {
    for_each = databricks_group.role
    content {
      principal  = grant.value.display_name
      privileges = ["USE_CATALOG"]
    }
  }

  depends_on = [databricks_catalog.warehouse]
}

resource "databricks_grants" "raw" {
  for_each = local.raw_schemas
  schema   = "${var.catalog}.${databricks_schema.layer[each.key].name}"

  grant {
    principal  = databricks_group.role["data-loaders"].display_name
    privileges = ["USE_SCHEMA", "CREATE_TABLE", "MODIFY", "SELECT", "READ_VOLUME"]
  }

  grant {
    principal  = databricks_group.role["data-builders"].display_name
    privileges = ["USE_SCHEMA", "SELECT", "READ_VOLUME"]
  }
}

resource "databricks_grants" "models" {
  for_each = merge(local.model_schemas, local.mart_schemas)
  schema   = "${var.catalog}.${databricks_schema.layer[each.key].name}"

  grant {
    principal  = databricks_group.role["data-builders"].display_name
    privileges = ["USE_SCHEMA", "CREATE_TABLE", "CREATE_FUNCTION", "MODIFY", "SELECT"]
  }

  dynamic "grant" {
    for_each = contains(keys(local.mart_schemas), each.key) ? ["data-readers"] : []
    content {
      principal  = databricks_group.role[grant.value].display_name
      privileges = ["USE_SCHEMA", "SELECT"]
    }
  }
}

data "databricks_sql_warehouse" "dbt" {
  name = var.sql_warehouse_name
}
