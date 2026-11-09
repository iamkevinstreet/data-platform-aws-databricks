# infra

Two Terraform roots, each with its own state, so the cloud account and the workspace can be built
and torn down apart. CI checks the format and validates both against their providers' schemas on
every push. The aws root was first applied on Nov 9, 2026, from data-platform; the databricks root
has not been applied yet.

## aws

The lake bucket and the role GitHub Actions assumes to write to it.

- The bucket: every public-access switch on, objects owned by the bucket, AES-256 encryption,
  versioning, replaced versions expired after 30 days, and TLS required by its policy.
- GitHub's OIDC provider (or the account's existing one, with `create_oidc_provider = false`).
- `data-platform-ci`: trusted for the main branch of each repository in `deployers`
  ([variables.tf](aws/variables.tf)) only, for an hour at most, allowed to list the bucket and to
  read and add objects, never to delete them. GitHub names the owner and the repository by id as
  well as by name in the OIDC subject of every repository made after July 15, 2026, so a deleted
  repository's name cannot be reused to assume the role. When AWS refuses a sign-in, a deploying
  repository's workflow can print the claims it offered, never the token, to match them here.

The first time, and after any change, from AWS CloudShell, signed in to the account (no key is
created or stored). `BUCKET` is the lake bucket's name: 3 to 55 lowercase letters, numbers and
hyphens, unique across AWS. The first time, choose one; the script refuses the README's
placeholder and any name another account holds:

```bash
git clone https://github.com/iamkevinstreet/data-platform-aws-databricks
cd data-platform-aws-databricks
BUCKET=YOUR-LAKE-NAME bash infra/bootstrap.sh
```

After that, the bucket already exists, so its name can be read from the account instead of typed:

```bash
BUCKET="$(aws s3api list-buckets --query "Buckets[?ends_with(Name, '-tfstate')].Name" \
  --output text | sed 's/-tfstate$//')" bash infra/bootstrap.sh
```

[`bootstrap.sh`](bootstrap.sh) installs Terraform if CloudShell lacks it, makes (or finds) a
private, versioned state bucket named after the lake bucket, writes the root's `backend.hcl`
(ignored by git), and applies the root in CloudShell's region, showing the plan and waiting for a
yes. It prints what to set in each deploying repository's Actions settings: the secrets
`AWS_ROLE_ARN` and `LAKE_BUCKET`, which name the account and stay masked in the public logs, and
the variable `AWS_REGION`. The state lives in the state bucket, not in the clone, so any fresh
clone with the same name picks up where the last one left off.

## databricks

Every Unity Catalog object a deploying project's warehouse needs, so a deleted Free Edition
workspace can be rebuilt from here: the catalog, one schema per layer, a managed `exports` volume
for files to load, and three groups with their grants. Loaders write the raw schemas; builders
read raw and own every model; readers see the published marts only. Grants are authoritative, so
the catalog's are set only on a catalog this root created.

```bash
cd infra/databricks
export DATABRICKS_HOST=... DATABRICKS_TOKEN=...   # a workspace token; workspace APIs only
terraform init -backend-config=backend.hcl       # the state bucket, key databricks/terraform.tfstate
terraform apply                                  # or -var create_catalog=false -var catalog=workspace
```

This root is optional for the first loads: dlt and dbt create their own schemas in the catalog a
deploying repository's `DATABRICKS_CATALOG` variable names, such as the Free Edition's own
`workspace`. That repository reads three secrets: `DATABRICKS_HOST` (the SQL warehouse's server
hostname, without `https://`), `DATABRICKS_HTTP_PATH` (its HTTP path, also this root's output
`sql_warehouse_http_path`) and `DATABRICKS_TOKEN`, a personal access token scoped to `sql`,
`files` and `unity-catalog`.

## Not yet known

These depend on what the Databricks Free Edition allows, and are checked on the first apply:
whether a workspace token may create a catalog and groups, whether Unity Catalog grants and managed
volumes are open to it, and whether it can read this account's bucket through an external location.
