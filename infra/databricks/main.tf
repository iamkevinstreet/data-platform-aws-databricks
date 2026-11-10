# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-10
#
# Every Unity Catalog object the warehouse needs, so a deleted workspace
# is rebuilt from this repository: the catalog, one schema per layer and
# one for each load's staging, a landing volume for exported files, and
# what each of three groups may do. Loaders write the raw schemas only;
# builders read raw and own the models; readers see the published marts
# and nothing under them. The groups are made in the workspace's
# settings, not here: a group made through a workspace's own API is
# workspace-local, and Unity Catalog grants nothing to one.

locals {
  raw_schemas = {
    raw_ai_ops     = "AI operations: the apps' committed results, loaded by dlt at pinned commits."
    raw_reviews    = "EEOC charge intake: review exports under contract v1, names masked."
    raw_eeoc_stats = "EEOC charge intake: the EEOC's Table E1a, charge receipts by basis."
  }
  # dlt merges each load through a schema of its own beside the dataset,
  # named with _staging, and stages its files in a volume there.
  load_schemas = {
    for name in keys(local.raw_schemas) :
    "${name}_staging" => "dlt's staging for ${name}: each load's rows before they merge."
  }
  landing_schemas = {
    landing = "Files dropped for loading, such as review exports."
  }
  model_schemas = {
    staging      = "dbt staging views: one per raw table, named for its source."
    intermediate = "dbt views that line each project's sources up to one grain."
    reference    = "dbt seeds: reference tables kept in each project's repository."
  }
  mart_schemas = {
    ai_ops   = "The AI operations mart: runs, cases, calls, spans and costs."
    charges  = "The EEOC charges mart: reviewed charges, field reviews, bridges and dimensions."
    national = "The EEOC's national statistics, the charges' context."
  }
  schemas = merge(
    local.raw_schemas, local.load_schemas, local.landing_schemas,
    local.model_schemas, local.mart_schemas,
  )

  # What loaders may do where they land data: make and merge into
  # tables, keep the functions their column masks call, stage files.
  loading = [
    "USE_SCHEMA", "CREATE_TABLE", "CREATE_FUNCTION", "CREATE_VOLUME",
    "MODIFY", "SELECT", "READ_VOLUME", "WRITE_VOLUME",
  ]

  # What builders may do in the schemas dbt writes: make, replace and
  # read tables and views.
  building = ["USE_SCHEMA", "CREATE_TABLE", "MODIFY", "SELECT"]

  # What reading is: the schema and its tables, no more.
  reading = ["USE_SCHEMA", "SELECT"]
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

# Each group may use the catalog. One grant per group leaves the
# catalog's other grants as they are, so this is safe on a catalog
# others share, such as the Free Edition's workspace.
resource "databricks_grant" "catalog" {
  for_each   = tomap(var.groups)
  catalog    = var.catalog
  principal  = each.value
  privileges = ["USE_CATALOG"]

  depends_on = [databricks_catalog.warehouse]
}

# The schemas below are this root's own, so their grants are
# authoritative: any grant not written here is removed.
resource "databricks_grants" "raw" {
  for_each = merge(local.raw_schemas, local.load_schemas, local.landing_schemas)
  schema   = "${var.catalog}.${databricks_schema.layer[each.key].name}"

  grant {
    principal  = var.groups.loaders
    privileges = local.loading
  }

  # Builders read what was loaded; staging and landing are the loaders'.
  dynamic "grant" {
    for_each = contains(keys(local.raw_schemas), each.key) ? [var.groups.builders] : []
    content {
      principal  = grant.value
      privileges = local.reading
    }
  }
}

resource "databricks_grants" "models" {
  for_each = merge(local.model_schemas, local.mart_schemas)
  schema   = "${var.catalog}.${databricks_schema.layer[each.key].name}"

  grant {
    principal  = var.groups.builders
    privileges = local.building
  }

  # Readers see the marts, never the views and seeds under them.
  dynamic "grant" {
    for_each = contains(keys(local.mart_schemas), each.key) ? [var.groups.readers] : []
    content {
      principal  = grant.value
      privileges = local.reading
    }
  }
}

data "databricks_sql_warehouse" "dbt" {
  name = var.sql_warehouse_name
}
