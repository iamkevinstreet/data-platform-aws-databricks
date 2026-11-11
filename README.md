# Data platform: AWS with Databricks

[![ci](https://github.com/iamkevinstreet/data-platform-aws-databricks/actions/workflows/ci.yml/badge.svg)](https://github.com/iamkevinstreet/data-platform-aws-databricks/actions/workflows/ci.yml)
[![codeql](https://github.com/iamkevinstreet/data-platform-aws-databricks/actions/workflows/codeql.yml/badge.svg)](https://github.com/iamkevinstreet/data-platform-aws-databricks/actions/workflows/codeql.yml)

Where projects run on AWS with Databricks. Every project follows the same blueprint, and this is
its bottom layer: the place its data lands and its warehouse runs. This repository provisions it,
in Terraform: a private S3 lake bucket, the role a project's GitHub workflows assume to write to
it, with no stored keys, and the Unity Catalog setup a project's loads and models run in. It is
the first of six platform repositories, one for each pairing of AWS, Azure or Google Cloud with
Databricks or Snowflake.

Case study: <https://kevindstreet.com/projects/data-platforms-databricks-snowflake/>

## Status

| Part | State |
| --- | --- |
| The aws root: the lake bucket and the CI role | Applied on Nov 9, 2026, from data-platform, where it was built; moved here unchanged but for the role's trust, which lists the deploying repositories. v0.2.0 added eeoc-charge-intake to them, applied on Nov 10 |
| The databricks root: catalog, schemas, volume, grants | Applied on Nov 10, 2026: the `kds` catalog, made in the workspace's UI since the Free Edition's API cannot make one on its default storage, then 13 schemas, the landing volume and each account group's grants. Both projects have loaded and built there since, with the charging party's name masked |
| Deploying here | [ai-operations](https://github.com/iamkevinstreet/ai-operations) and [eeoc-charge-intake](https://github.com/iamkevinstreet/eeoc-charge-intake): every day each loads and builds on Databricks, and copies its warehouse and docs to the lake under its own prefix |

The Databricks Free Edition runs in Databricks' own hosting, not in this AWS account. A Databricks
workspace inside this account, reading the lake through Unity Catalog, needs a Databricks trial;
that is the next step for this pairing.

## What it provides

| Piece | What it is | Where |
| --- | --- | --- |
| Lake bucket | Private, encrypted, versioned, TLS only; replaced versions expire after 30 days | [infra/aws/main.tf](infra/aws/main.tf) |
| CI role, `data-platform-ci` | Assumed through GitHub's OIDC token by the main branch of each listed repository, for an hour at most; lists, reads and adds objects, never deletes | [infra/aws/main.tf](infra/aws/main.tf) |
| Deployers | The repositories the role trusts, each by owner/name and numeric id | [infra/aws/variables.tf](infra/aws/variables.tf) |
| Unity Catalog setup | A catalog, a schema per layer and per load's staging, a landing volume, and what each of three groups may do: load, build or read | [infra/databricks/main.tf](infra/databricks/main.tf) |
| Bootstrap | Builds or changes the aws root from AWS CloudShell, with its state in a private bucket | [infra/bootstrap.sh](infra/bootstrap.sh) |
| Databricks apply | Applies the databricks root from AWS CloudShell, its state beside the aws root's, with a workspace token typed in and never stored | [infra/databricks.sh](infra/databricks.sh) |

## How a project deploys here

1. Add its repository to `deployers` in [infra/aws/variables.tf](infra/aws/variables.tf), by
   owner/name and numeric id (`gh api repos/OWNER/NAME --jq .id`), and apply the aws root again.
2. In that repository's Actions settings, set the secrets `AWS_ROLE_ARN` and `LAKE_BUCKET` (the
   bootstrap prints both) and the variable `AWS_REGION`; for Databricks, the secrets
   `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH` and `DATABRICKS_TOKEN` and the variable
   `DATABRICKS_CATALOG`.
3. Write under the project's own prefix in the lake, `s3://LAKE_BUCKET/PROJECT/`.

Anything that names the account is a secret, not a variable, because a public repository's logs
are public.

## Set up or change it

From AWS CloudShell, as [infra/README.md](infra/README.md) describes: clone this repository and run
the bootstrap with the lake bucket's name. Terraform shows its plan and waits for a yes; read the
plan before answering, as it should change only what was edited.

## The pairings

The same projects, deployed on each pairing and measured the same way. This repository's row is
in bold.

| Pairing | Setup | The EEOC's daily run | AI operations' daily run | Cost | Who the jobs run as |
| --- | --- | --- | --- | --- | --- |
| **AWS with Databricks (Free Edition)** | **Terraform from CloudShell with a workspace token; account groups made by hand** | **Loads in 55 s and 17 s, then all 127 seeds, models and tests in 70 s** | **Load in 58 s, then all 128 in 68 s** | **Nothing** | **One person's token, the owner of what it makes; a column mask hides names from everyone** |
| [AWS with Snowflake](https://github.com/iamkevinstreet/data-platform-aws-snowflake) (trial) | Terraform from CloudShell with a key that never leaves it | Loads in 32 s and 22 s, then all 127 seeds, models and tests in 30 s | Load in 34 s, then all 128 in 32 s | Trial credits: 0.082 for the EEOC's daily run and 0.079 for AI operations' on Nov 11, under a 20-credit monthly quota | A service user per job, by GitHub's OIDC token; a masking policy hides names from every role |

Measured in the same daily runs on Nov 10, on the same commits: eeoc-charge-intake's
[42887179186](https://github.com/iamkevinstreet/eeoc-charge-intake/actions/runs/42887179186) and
ai-operations' [42887184672](https://github.com/iamkevinstreet/ai-operations/actions/runs/42887184672).
A load runs from its command's start to dlt's report that it finished, the EEOC's review exports
first, then the EEOC's national table; a build is dbt's own clock. Snowflake's credits are from the
scheduled runs of Nov 11, which fell in different hours, so each project's show on their own; that
platform's [README](https://github.com/iamkevinstreet/data-platform-aws-snowflake#costs) has them
by warehouse.

## Costs

The bucket holds a few megabytes, which cost cents a month; the role and GitHub's OIDC provider
cost nothing, and so does the Databricks Free Edition. Nothing here runs between deployments.

## Layout

```text
infra/aws/          the lake bucket, GitHub's OIDC provider and the CI role
infra/databricks/   the Unity Catalog objects and their grants
infra/bootstrap.sh  the aws root's first apply, and every later one, from AWS CloudShell
infra/databricks.sh the databricks root's apply, from AWS CloudShell
infra/terraform.sh  what both scripts share: Terraform's install and the state bucket
tests/              the Terraform read without a cloud account
```

## Testing

```bash
make install   # the checks' environment, from uv.lock
make check     # lint, format, strict types and the code standard
make test      # 7 tests: the Terraform parsed and its rules checked
```

CI also runs `terraform fmt` and `terraform validate` on both roots.

## Changelog and license

[CHANGELOG.md](CHANGELOG.md) lists every change, and [SECURITY.md](SECURITY.md) how to report a
vulnerability. Licensed under the [Apache License 2.0](LICENSE).
