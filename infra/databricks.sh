#!/usr/bin/env bash
########################################################################
#                                                                      #
#                         infra/databricks.sh                          #
#                                                                      #
########################################################################
# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# Applies the databricks root from AWS CloudShell, its state in the
# bootstrap's state bucket beside the aws root's. Asks for the
# workspace's address and a workspace token, which stay in this
# script's environment: never printed, never written to a file. Then
# Terraform shows its plan and waits for a yes.
#
#   bash infra/databricks.sh
#
# Make the groups and the catalog in the workspace first, as
# infra/README.md says. Arguments are passed to terraform apply, such
# as -var create_catalog=true where the API can make the catalog.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/databricks" && pwd)"
# shellcheck source=infra/terraform.sh
source "$(dirname "$0")/terraform.sh"

# The state bucket, and its region, which the backend needs.
STATE="$(state_bucket)"
REGION="$(aws s3api get-bucket-location --bucket "${STATE}" \
  --query LocationConstraint --output text)"
if [[ "${REGION}" == "None" ]]; then
  REGION="us-east-1"
fi

# The workspace, with or without its https://, and a token for it.
read -rp "Databricks workspace address, as in your browser's address bar: " host
read -rsp "Workspace token (not shown as you type): " DATABRICKS_TOKEN
echo
host="${host#https://}"
host="${host%%/*}"
host="${host%%\?*}"
if [[ -z "${host}" || -z "${DATABRICKS_TOKEN}" ]]; then
  echo "Give both the workspace's address and a token." >&2
  exit 1
fi
DATABRICKS_HOST="https://${host}"
export DATABRICKS_HOST DATABRICKS_TOKEN

# Terraform, installed when this CloudShell session lacks it.
ensure_terraform

# Providers run to hundreds of megabytes: keep them out of the home.
export TF_DATA_DIR="${TMPDIR:-/tmp}/data-platform-aws-databricks-terraform/databricks"

# The root's backend, written beside it; git ignores backend.hcl.
cat > "${ROOT}/backend.hcl" <<EOF
bucket       = "${STATE}"
key          = "databricks/terraform.tfstate"
region       = "${REGION}"
encrypt      = true
use_lockfile = true
EOF

terraform -chdir="${ROOT}" init -input=false -backend-config=backend.hcl
# Shows the plan and waits for a yes; -input=false would refuse instead.
terraform -chdir="${ROOT}" apply "$@"

echo
echo "Done. In each deploying repository: Settings, Secrets and variables, Actions."
echo "  Variable  DATABRICKS_CATALOG = $(terraform -chdir="${ROOT}" output -raw catalog)"
