# Changelog

## v0.3.0, Nov 10, 2026

- **Grants go to account groups, made in the workspace's settings.** The databricks root made its
  three groups with the workspace's token, which makes workspace-local groups, and Unity Catalog
  cannot grant to those; the root had not been applied, so nothing was lost. It now names
  `data-loaders`, `data-builders` and `data-readers` in a `groups` variable, made once by hand
  as account groups, which infra/README.md walks through.
- **Each group reaches only what its job needs.** Loaders make and merge into the raw tables, keep
  their column masks' functions and stage files; builders read the raw datasets and write the models
  and marts; readers read the marts alone. dlt's staging schemas (`raw_*_staging`) are made here
  and are the loaders' alone, and the `landing` schema is no longer readable by builders. The
  catalog's grants are one per group, so they are safe on a catalog others share.
- **`infra/databricks.sh` applies the databricks root** from AWS CloudShell, its state in the
  bootstrap's state bucket under `databricks/`, asking for the workspace's address and a token that
  it never prints or stores. What it shares with the bootstrap, Terraform's install and finding
  the state bucket, moved to `infra/terraform.sh`.
- 7 tests.

## v0.2.0, Nov 9, 2026

- **eeoc-charge-intake deploys here.** The CI role trusts its main branch, by name and id
  (1418185196), beside ai-operations', and the old `data-platform` name is gone, the rename being
  done. A repository may now appear in `deployers` only once, by id. Applying this version
  changes only the role's trust policy.
- **The databricks root makes the EEOC's schemas:** `raw_reviews` and `raw_eeoc_stats` for its
  loads, and the `charges` and `national` marts; the staging, intermediate and reference schemas
  are shared, since every model is named for its source.
- **Dependency updates land by themselves.** Dependabot groups each week's updates into one pull
  request per kind (Actions, the Python checks, the Terraform providers), and the
  `dependency-updates` workflow lands them every weekday: it applies the oldest open one to `main`
  as an ordinary commit, refreshes the dates in the headers it changes, runs the whole of CI on that
  commit, and moves `main` to it only when every check passes. One whose checks fail is labelled
  "needs a person" and waits; one that changes a workflow waits for the `DEPENDENCY_UPDATES_TOKEN`
  secret. CI can now be called for a given commit, which is how the workflow checks one.
- 5 tests.

## v0.1.0, Nov 9, 2026

- **Split from data-platform**, now [ai-operations](https://github.com/iamkevinstreet/ai-operations),
  at commit 8c6b715, where the history of these files is. A project and the platform it runs on
  are separate repositories now: this one holds the platform for AWS with Databricks, and any
  project deploys onto it.
  - The aws root: the lake bucket, GitHub's OIDC provider and the CI role, applied from
    data-platform on Nov 9.
  - The databricks root: the catalog, schemas, landing volume, groups and grants, not yet applied.
  - The bootstrap, and the tests that read the Terraform without a cloud account.
- **The CI role trusts a list of repositories**, `deployers`, each by owner/name and numeric id,
  where it trusted one. It lists ai-operations, and data-platform, the same repository under its
  name before the rename, until the rename is done; both share one id, so no other repository can
  match the old name. The bucket, the role's name and its ARN are unchanged, so applying this
  version changes only the role's trust policy and its description.
- **The databricks root no longer makes `raw_eeoc_stats`.** The EEOC's national statistics move to
  eeoc-charge-intake with its charge warehouse.
- 5 tests.
