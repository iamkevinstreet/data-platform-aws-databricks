# Security

## Reporting a vulnerability

Please report it privately, never in a public issue:

- **Preferred:** GitHub's private vulnerability reporting (the repository's **Security** tab, then
  **Report a vulnerability**).
- **Otherwise:** email info@kevindstreet.com with "Security" in the subject.

Include what you found, how to reproduce it, and what an attacker could do with it. You will get an
answer within 3 business days. A confirmed issue is fixed within 30 days, sooner when severe, and you
are credited in the advisory unless you would rather not be.

## Scope

In scope: the Terraform in `infra/`, the bootstrap, the tests and the workflows in `.github/`, and
above all any way to widen the CI role's rights, to let a repository that is not listed assume it,
or to make the lake or the state bucket readable by anyone else.

Out of scope: the projects that deploy here, which have their own repositories, GitHub, AWS and
Databricks themselves, and findings that need a compromised developer machine.

## How this repository is protected

| Risk | Control |
| --- | --- |
| A key for AWS that could leak | None exists: workflows assume an IAM role through GitHub's OIDC token, trusted for the main branch of the listed repositories only, by name and numeric id, for an hour at most |
| A role that can do too much | It can list the lake bucket and read and add objects; it can never delete; a test checks the policy |
| A public bucket | Every public-access switch on, objects owned by the bucket, TLS required, versioning on; a test checks the Terraform |
| Terraform state anyone can read | The state bucket is private, versioned and encrypted, and is made by the bootstrap from CloudShell, signed in as the account's owner; no state is committed |
| A committed secret | gitleaks before every commit and over the whole history in CI; anything that names the account lives in GitHub secrets only |
| A vulnerable dependency | A lockfile with hashes, `pip-audit` in CI, Dependabot every week for the Actions, the Python checks and the Terraform providers |
| A tampered Action or tool | Actions pinned to commit SHAs; the gitleaks download checked against its published SHA-256; the Terraform zip, when the bootstrap needs it, checked against HashiCorp's published SHA-256 |
