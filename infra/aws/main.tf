# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# The lake bucket and the role GitHub Actions assumes to write to it.
# The bucket is private, encrypted, versioned and TLS-only; the role has
# no keys to leak: a workflow on main of a deploying repository gets it
# through GitHub's OIDC token for an hour at most, and it can list, read
# and add objects in this bucket only, never delete them.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "data-platform"
      managed_by = "terraform"
    }
  }
}

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  github_oidc_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )

  # GitHub's OIDC subject names the owner and the repository by name and
  # by id, so a deleted repository's name cannot be taken over. It is the
  # default for every repository made after July 15, 2026.
  github_subjects = [
    for d in var.deployers : format(
      "repo:%s@%d/%s@%d:ref:%s",
      split("/", d.repository)[0],
      var.github_owner_id,
      split("/", d.repository)[1],
      d.id,
      var.github_ref,
    )
  ]
}

resource "aws_s3_bucket" "lake" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "expire-replaced-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.lake.arn,
      "${aws_s3_bucket.lake.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "lake" {
  bucket = aws_s3_bucket.lake.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.lake]
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = local.github_oidc_url
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "data-platform-ci"
  description          = "Assumed by deploying workflows on main through GitHub's OIDC token."
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci_lake" {
  statement {
    sid       = "ListTheLake"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lake.arn]
  }

  statement {
    sid       = "ReadAndAddObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.lake.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ci_lake" {
  name   = "lake-read-and-add"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_lake.json
}
