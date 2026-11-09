# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# What the workflows need from this root: the bucket and the role ARN,
# which go in the repository's secrets, never in a file or a log.

output "bucket_name" {
  description = "The lake bucket's name; set it as the LAKE_BUCKET repository secret."
  value       = aws_s3_bucket.lake.bucket
}

output "ci_role_arn" {
  description = "The role the workflows assume; set it as the AWS_ROLE_ARN repository secret."
  value       = aws_iam_role.ci.arn
}
