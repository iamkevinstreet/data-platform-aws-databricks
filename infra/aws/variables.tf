# Author:            Kevin Street
# Created on:        2026-11-09
# Last modified on:  2026-11-09
#
# What changes between accounts: the region, the bucket's name, and the
# repositories and branch whose workflows may assume the CI role, by
# name and by GitHub's numeric ids.

variable "region" {
  description = "The AWS region the bucket and role live in."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "The bucket's name; bucket names are global, so it is set per account."
  type        = string
}

variable "deployers" {
  description = "Repositories whose workflows on main may assume the role, by owner/name and id."
  type = list(object({
    repository = string
    id         = number
  }))
  default = [
    { repository = "iamkevinstreet/ai-operations", id = 1450000844 },
    # The same repository under its name before the Nov 9, 2026 rename. Its id
    # is the same, so no other repository can match it; drop it once renamed.
    { repository = "iamkevinstreet/data-platform", id = 1450000844 },
  ]

  validation {
    condition = length(var.deployers) > 0 && alltrue([
      for d in var.deployers : length(split("/", d.repository)) == 2
    ])
    error_message = "Name at least one deployer, each as owner/name."
  }
}

variable "github_owner_id" {
  description = "The repositories' owner's numeric GitHub id, part of the OIDC subject."
  type        = number
  default     = 747156
}

variable "github_ref" {
  description = "The only branch whose workflows may assume the role."
  type        = string
  default     = "refs/heads/main"
}

variable "create_oidc_provider" {
  description = "Whether to create GitHub's OIDC provider; false when the account already has it."
  type        = bool
  default     = true
}
