# Changelog

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
