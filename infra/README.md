# infra

Two Terraform roots, each with its own state, so the cloud account and the workspace can be built
and torn down apart. CI checks the format and validates both against their providers' schemas on
every push. The aws root was first applied on Nov 9, 2026, from data-platform; the databricks root
has not been applied yet. Each is applied from AWS CloudShell by a script, which shows Terraform's
plan and waits for a yes.

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
workspace can be rebuilt from here: the catalog (`kds`), a schema for each raw dataset and one
beside it for dlt's staging, a `landing` schema with a managed `exports` volume, the model and mart
schemas, and what each of three groups may do in them.

| Group | Raw and staging schemas | Staging, intermediate and reference | Marts |
| --- | --- | --- | --- |
| `data-loaders` | make tables and their masks' functions, merge, stage files | nothing | nothing |
| `data-builders` | read the raw datasets | make and replace tables and views | make and replace |
| `data-readers` | nothing | nothing | read |

Each group may use the catalog. The schemas' grants are authoritative, since the schemas are this
root's own; the catalog's are one per group, which leaves any other grant on it alone.

**The groups are made in the workspace, not here.** A group the Databricks provider makes with a
workspace's token is workspace-local, and Unity Catalog grants nothing to a workspace-local group;
making an account group takes the account console, which the Free Edition does not have. A group a
workspace admin adds in the workspace's settings is an account group. So, once, before the first
apply: in the workspace, open Settings, then Identity and access, then Manage next to Groups, then
Add group, and add `data-loaders`, `data-builders` and `data-readers`, plus `personal-data-readers`,
the one group eeoc-charge-intake's column mask lets see a charging party's name. All four stay
empty. The dialog, Add group to account and workspace, also sets each group's entitlements:

| Group | Consumer access | Databricks SQL access | Workspace access | Admin access |
| --- | --- | --- | --- | --- |
| `data-loaders` | off | on | off | off |
| `data-builders` | off | on | off | off |
| `data-readers` | off | on | off | off |
| `personal-data-readers` | on | off | off | off |

The loads, the builds and anyone reading the marts reach Databricks only through the SQL warehouse,
so SQL access is all a working group needs: no notebooks or clusters, no consumer view, no admin.
`personal-data-readers` exists only for the mask to ask who is in it. The dialog will not add a
group with no entitlement, so it gets the narrowest, consumer access, which opens no data by itself:
what anyone reads still comes from Unity Catalog's grants, and this group has none.
Entitlements add up across a member's groups, and on the Free Edition every job runs with one
person's token, so these bind whoever is added to a group later, not today's runs.

Then, from AWS CloudShell, with a workspace token (Settings, then Developer, then Access tokens; a
day's lifetime is enough):

```bash
cd data-platform-aws-databricks
git pull
bash infra/databricks.sh
```

[`databricks.sh`](databricks.sh) asks for the workspace's address and the token, which stay in its
environment and are never printed or written to a file, installs Terraform if CloudShell lacks it,
keeps the root's state in the bootstrap's state bucket under `databricks/`, and applies the root,
showing the plan and waiting for a yes. Then set each deploying repository's `DATABRICKS_CATALOG`
variable to `kds`; its next run loads and builds there.

If the apply cannot make the catalog (in February 2026 some Free Edition users could make one only
from SQL), make it in the SQL editor with `CREATE CATALOG kds` and run the script again with
`-var create_catalog=false`.

A deploying repository reads three secrets: `DATABRICKS_HOST` (the SQL warehouse's server
hostname, without `https://`), `DATABRICKS_HTTP_PATH` (its HTTP path, also this root's output
`sql_warehouse_http_path`) and `DATABRICKS_TOKEN`, a personal access token scoped to `sql`,
`files` and `unity-catalog`.

## Found out, and not yet known

- **Groups:** the provider's `databricks_group`, with a workspace's token, makes a workspace-local
  group, which Unity Catalog cannot grant to ([Databricks: workspace-local
  groups](https://docs.databricks.com/aws/en/admin/users-groups/workspace-local-groups); the
  provider's issues [#3412](https://github.com/databricks/terraform-provider-databricks/issues/3412)
  and [#5174](https://github.com/databricks/terraform-provider-databricks/issues/5174)). Hence the
  groups made by hand above.
- **Who runs the jobs:** every load and build runs with one person's token, the owner of what it
  makes, so the grants bind every other principal but not the jobs. A service principal for each
  job would make them bite; forum reports say the Free Edition cannot give a service principal an
  OAuth secret, which needs the account console. Not yet tried.
- **Still to learn on the first apply:** whether the token may make a catalog, whether managed
  volumes are open to it, and whether it can read this account's bucket through an external
  location.
