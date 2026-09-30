# Public release boundary

Publish only reusable source, placeholder examples, the MIT license, and the reviewed documentation linked from the README. Live deployment records and credentials are not part of this project release.

## Included files

- Root: `README.md`, `LICENSE`, and `.gitignore`.
- Terraform: `.tf` source, `.terraform.lock.hcl`, and `terraform.tfvars.example`.
- Deployment: Compose files, Prometheus/Grafana provisioning, Runner template and smoke pipeline, and `deploy/gitlab/.env.example`.
- Scripts: host preparation, disk preparation, and GitLab/Grafana backups.
- Documentation: SAD with ADRs and Mermaid diagrams, deployment, VPN, recovery, and this publishing guide.

The explicit documentation allowlist in `.gitignore` leaves operator records, historical screenshots, drawings, and private VPN notes excluded. Do not force-add them. `.gitignore` does not protect a file already tracked or remove anything from history.

## Before publishing

1. Review `git status --short`, `git diff`, and `git ls-files`. Ensure examples contain placeholders, not your subscription, tenant, domain, storage account, or credential values.
2. Scan the exact release contents and all history you intend to publish for private keys, certificates, tokens, credentials, state, archives, local paths, and private identifiers. Review author/committer names and emails, remote URLs, tags, branches, and commit messages too. Pattern scans reduce risk but cannot prove that every possible secret is absent.
3. Publish a clean reviewed file export in a new repository if existing Git metadata must stay private. Do not copy `.git`, ignored files, or the entire working directory. Set your chosen public author identity before creating the first commit. Avoid rewriting or force-pushing the existing repository as a shortcut.
4. Run Terraform format/validation, Compose validation with an example hostname, Prometheus configuration validation, Bash syntax checks, and local documentation link checks. These do not replace runtime acceptance.
5. Review the destination repository's visibility, branches/tags, issues, merge/pull requests, CI logs/artifacts, wiki, releases, and attachments before making it public. A source cleanup cannot remove material already copied or indexed elsewhere. If a credential was exposed, rotate it; deleting its file alone is insufficient.

## What this does not expose

Publishing configuration does not grant access to the deployed platform or change Azure resource visibility. The design has no public VM IPs, but the VPN gateway is publicly reachable and Blob uses an authenticated public endpoint. The [SAD](SOLUTION_ARCHITECTURE.md#2-network-and-infrastructure) explains those boundaries.

Private RFC 1918 addresses, example resource names, service ports, and the architecture itself are intentionally documented so readers can understand and reproduce the design. No live platform availability or successful runtime acceptance is implied by a public release.
