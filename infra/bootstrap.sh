#!/usr/bin/env bash
########################################################################
#                                                                      #
#                          infra/bootstrap.sh                          #
#                                                                      #
########################################################################
# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# Builds the AWS side once, from AWS CloudShell, signed in as the
# account's owner: a private, versioned state bucket, then the aws root
# (the lake bucket and the CI role) with its state in that bucket, in
# CloudShell's region. Safe to run again with the same name; it changes
# only what differs, and finds the state where it was left.
#
#   BUCKET=YOUR-LAKE-NAME bash infra/bootstrap.sh
#
# with a name of your own: 3 to 55 lowercase letters, numbers and
# hyphens, unique across AWS. Terraform shows its plan and waits for a
# yes before it changes anything. Then set what it prints in each
# deploying repository's Actions settings: the secrets AWS_ROLE_ARN and
# LAKE_BUCKET, and the variable AWS_REGION. No key is created, printed
# or stored.

set -euo pipefail

: "${BUCKET:?set BUCKET to a name of your own for the lake bucket}"
REGION="${AWS_REGION:-us-east-1}"
STATE="${BUCKET}-tfstate"
ROOT="$(cd "$(dirname "$0")/aws" && pwd)"
REPO="https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo"

# A bucket name, short enough for the state bucket's -tfstate to fit.
if [[ ! "${BUCKET}" =~ ^[a-z0-9][a-z0-9-]{1,53}[a-z0-9]$ ]]; then
  echo "BUCKET must be 3 to 55 lowercase letters, numbers and hyphens, not ${BUCKET}" >&2
  exit 1
fi

# A name another account holds cannot be had; stop before making anything.
for name in "${BUCKET}" "${STATE}"; do
  if ! out="$(aws s3api head-bucket --bucket "${name}" 2>&1)" && [[ "${out}" == *"403"* ]]; then
    echo "The bucket name ${name} belongs to another AWS account; choose another BUCKET." >&2
    exit 1
  fi
done

# Terraform from its official zip, checked against HashiCorp's checksums.
install_terraform_zip() {
  local version arch dir
  version="$(curl -fsS https://checkpoint-api.hashicorp.com/v1/check/terraform \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["current_version"])')"
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "No Terraform build for $(uname -m)" >&2; exit 1 ;;
  esac
  dir="$(mktemp -d)"
  curl -fsSLo "${dir}/terraform_${version}_linux_${arch}.zip" \
    "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_${arch}.zip"
  curl -fsSLo "${dir}/SHA256SUMS" \
    "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_SHA256SUMS"
  if ! (cd "${dir}" && grep "_linux_${arch}.zip" SHA256SUMS | sha256sum -c -); then
    echo "The Terraform download does not match HashiCorp's checksum" >&2
    exit 1
  fi
  unzip -q "${dir}/terraform_${version}_linux_${arch}.zip" -d "${dir}"
  sudo install -m 0755 "${dir}/terraform" /usr/local/bin/terraform
}

# Terraform, from HashiCorp's package repository, else its zip.
if ! command -v terraform >/dev/null 2>&1; then
  if ! { sudo dnf install -y dnf-plugins-core \
    && sudo dnf config-manager --add-repo "${REPO}" \
    && sudo dnf install -y terraform; }; then
    install_terraform_zip
  fi
fi

# Providers run to hundreds of megabytes; keep them out of the 1 GB home.
export TF_DATA_DIR="${TMPDIR:-/tmp}/data-platform-aws-databricks-terraform/aws"

# The state bucket: created once, then kept private, versioned and encrypted.
if ! aws s3api head-bucket --bucket "${STATE}" 2>/dev/null; then
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${STATE}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${STATE}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi
aws s3api put-public-access-block --bucket "${STATE}" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "${STATE}" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "${STATE}" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# The aws root's backend, written beside it; git ignores backend.hcl.
cat > "${ROOT}/backend.hcl" <<EOF
bucket       = "${STATE}"
key          = "aws/terraform.tfstate"
region       = "${REGION}"
encrypt      = true
use_lockfile = true
EOF

terraform -chdir="${ROOT}" init -input=false -backend-config=backend.hcl
# Shows the plan and waits for a yes; -input=false would refuse instead.
terraform -chdir="${ROOT}" apply -var "bucket_name=${BUCKET}" -var "region=${REGION}"

echo
echo "Set these in each deploying repository: Settings, Secrets and variables, Actions."
echo "  Secret    AWS_ROLE_ARN = $(terraform -chdir="${ROOT}" output -raw ci_role_arn)"
echo "  Secret    LAKE_BUCKET  = $(terraform -chdir="${ROOT}" output -raw bucket_name)"
echo "  Variable  AWS_REGION   = ${REGION}"
