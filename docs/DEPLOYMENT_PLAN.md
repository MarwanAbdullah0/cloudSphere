# Deployment runbook: two-VM GitLab platform

These commands are for an operator on the VPN. Review the Terraform plan before applying it and resolve DNS, certificate, and outbound connectivity before starting GitLab. Place deployment files at `/opt/platform` so the backup scripts' paths match. Do not copy `terraform.tfvars`, state, or the entire `certs/` directory to the VMs.

## Operator inputs and release status

This runbook describes installation, not the status of a particular deployment. Keep resource IDs, credentials, backup object names, and acceptance evidence in private operator records. Commands use the default `azureadmin` account; substitute your configured administrator if different.

Copy `terraform/terraform.tfvars.example` to ignored `terraform/terraform.tfvars`, and supply your subscription, globally unique storage account name, SSH public key path, and VPN root certificate path. See [VPN preparation](VPN.md) before applying the gateway configuration. Supply your own GitLab hostname and matching trusted TLS certificate. Verify Azure quota and the availability of the two selected 2-vCPU/8-GiB VM sizes.

For existing resources, retain the original Terraform state and reconcile imports/drift first. A fresh state is not a safe way to adopt an existing deployment. For a new installation, the plan creates the two VMs and two NICs; for an existing installation, neither VM should be replaced.

## 1. Plan Azure changes

On the admin machine, set a globally unique lowercase storage name in ignored `terraform/terraform.tfvars` as `backup_storage_account_name = "..."`. For an existing deployment, preserve its subscription and VPN values. From `terraform/`:

```bash
terraform init
terraform fmt -check compute.tf main.tf network.tf providers.tf security.tf storage.tf outputs.tf variables.tf vpn.tf
terraform validate
terraform plan -out=deployment.tfplan
terraform show deployment.tfplan
```

For an existing installation adding persistence, review for two new managed disks (128 and 64 GiB), attachments, storage account/container/lifecycle policy, two user-assigned identities, and two Blob role assignments. The plan must have **no `-/+` or `destroy` for either VM**, and both VM sizes must remain 2 vCPUs (4 total). Resolve drift and obtain deployment authorization before `terraform apply deployment.tfplan`. Review a fresh plan before every apply. This publication preparation does not authorize an apply. Use `terraform output` to obtain each backup identity client ID. Replace all `YOUR_...` values in commands below with those outputs and the storage account name. Record the disk LUN 0 attachments, wait for identity role propagation, and check that the Blob account can be reached from both VMs.

## 2. Prepare hosts and disks

Connect the VPN and check SSH to `azureadmin@10.0.1.10` and `azureadmin@10.0.3.10`. On each host, check `free -h`, `df -h`, `getent hosts download.docker.com`, and `curl -I https://download.docker.com`. Verify package, registry, and Blob HTTPS access before downloads. For example, on each VM (substitute your storage account):

```bash
getent hosts download.docker.com packages.microsoft.com registry-1.docker.io
curl -I --connect-timeout 10 https://download.docker.com
curl -I --connect-timeout 10 https://packages.microsoft.com
curl -I --connect-timeout 10 https://registry-1.docker.io/v2/
curl -I --connect-timeout 10 https://YOUR_STORAGE_ACCOUNT.blob.core.windows.net/
```

An HTTP authentication error from a registry or Blob proves endpoint connectivity, not permission; verify authenticated uploads separately. DNS success alone is insufficient. No NAT gateway or public VM IP is defined, so outbound connectivity requires a real check. After copying deployment files below, run `sudo bash /opt/platform/scripts/install-host-tools.sh` to install Docker Engine/Compose, Azure CLI, and SQLite using the vendors' apt repositories. Verify `sudo docker version`, `sudo docker compose version`, `az version`, and `sqlite3 --version`.

From a reviewed, committed release on the VPN-connected admin machine, archive only committed deployment files and scripts, then copy them to each VM. Uncommitted changes are not included:

```bash
git archive --format=tar.gz --output=/tmp/bootcamp-platform.tar.gz HEAD deploy scripts
for host in 10.0.1.10 10.0.3.10; do
  ssh "azureadmin@$host" 'mkdir -p ~/platform-transfer && chmod 700 ~/platform-transfer'
  scp /tmp/bootcamp-platform.tar.gz "azureadmin@$host:platform-transfer/"
  ssh "azureadmin@$host" 'sudo mkdir -p /opt/platform && sudo tar -C /opt/platform -xzf ~/platform-transfer/bootcamp-platform.tar.gz'
done
```

On each VM identify the **new LUN 0 data disk** by Azure LUN and stable serial; do not guess `/dev/sdX`:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL
ls -l /dev/disk/by-id/
```

Use the actual by-id path after confirming disk size and LUN. The script only formats a blank whole disk; it refuses any existing partition, signature, or nonzero data, scans the full disk (which can take time), then writes an UUID fstab entry. Run on GitLab VM:

```bash
sudo /opt/platform/scripts/prepare-data-disk.sh gitlab /dev/disk/by-id/REPLACE_WITH_GITLAB_DISK_ID
findmnt /srv/gitlab
```

Run on monitoring VM:

```bash
sudo /opt/platform/scripts/prepare-data-disk.sh monitoring /dev/disk/by-id/REPLACE_WITH_MONITORING_DISK_ID
findmnt /srv/monitoring
```

## 3. DNS and GitLab HTTPS

Choose `GITLAB_HOSTNAME` (for example `gitlab.internal.example.com`). Create DNS so VPN clients and `10.0.3.10` resolve it to `10.0.1.10` (`getent hosts <hostname>` on both). Obtain a trusted certificate for that name through DNS validation or a private CA trusted by clients and monitoring VM. GitLab's normal public HTTP certificate challenge cannot validate this private endpoint. Copy the full certificate chain and private key securely to `/srv/gitlab/config/ssl/<hostname>.crt` and `.key`, respectively. Restrict the key to root. Never commit either file. Distribute any private CA trust to client hosts and the monitoring VM/Docker jobs.

On the GitLab VM:

```bash
export GITLAB_HOSTNAME="gitlab.internal.example.com" # use your configured DNS name
sudo mkdir -p /srv/gitlab/config/ssl
sudo chmod 700 /srv/gitlab/config/ssl
sudo chmod 600 /srv/gitlab/config/ssl/*.key
cd /opt/platform/deploy/gitlab
sudo --preserve-env=GITLAB_HOSTNAME docker compose config --quiet
sudo --preserve-env=GITLAB_HOSTNAME docker compose up -d
sudo --preserve-env=GITLAB_HOSTNAME docker compose logs --tail=100 gitlab
sudo docker exec gitlab cat /etc/gitlab/initial_root_password
```

For later Compose commands, create a root-owned mode-600 `/opt/platform/deploy/gitlab/.env` containing `GITLAB_HOSTNAME=<your hostname>`, or continue passing the variable with `sudo --preserve-env`. Change the initial root password at first login; create local users and one test project. Host port 22 remains `azureadmin` SSH. Git over HTTPS uses port 443. Do not expose the GitLab container's SSH port on 22.

### Certificate renewal

Record the expiry and renewal method for your own certificate privately. Manual DNS validation does not renew automatically. Renew through your certificate issuer, install the renewed full chain and key at `/srv/gitlab/config/ssl/<hostname>.crt` and `.key`, keep the key root-owned with mode `600`, then reload NGINX:

```bash
sudo docker exec gitlab gitlab-ctl hup nginx
```

Check the served certificate from a VPN client before removing the previous certificate. Do not publish certificate material, DNS challenge records, or issuer account files.

## 4. Initial backup and complete restore test

Before installing monitoring services, create a test repository with a commit and run one full GitLab backup. Use the Blob account created by Terraform. On GitLab VM:

```bash
sudo env BACKUP_ACCOUNT="YOUR_STORAGE_ACCOUNT" BACKUP_CLIENT_ID="YOUR_GITLAB_IDENTITY_CLIENT_ID" /opt/platform/scripts/backup-gitlab.sh
sudo cat /srv/gitlab/backup-status/last-success
az login --identity --client-id "YOUR_GITLAB_IDENTITY_CLIENT_ID"
az storage blob list --auth-mode login --account-name YOUR_STORAGE_ACCOUNT --container-name platform-backups --prefix gitlab/ --output table
```

The first run is full because no predecessor exists. Follow [the restore runbook](runbooks/RESTORE.md) to restore this archive on the still-empty monitoring VM with the **same GitLab CE image version**, verify the test repository and database, and remove only the temporary restore containers/data after checking. This test must finish before installing Prometheus, Grafana, or Runner.

## 5. Monitoring and project Runner

On monitoring VM create a strong Grafana admin password in the data disk, without putting it in shell history:

```bash
sudo install -m 700 -d /srv/monitoring/secrets
sudo sh -c 'umask 077; cat > /srv/monitoring/secrets/grafana-admin-password'
# Type the password, then Ctrl-D.
sudo chown 472:472 /srv/monitoring/secrets/grafana-admin-password
cd /opt/platform/deploy/monitoring
sudo docker compose config --quiet
sudo docker compose up -d prometheus grafana node-exporter
sudo docker compose logs --tail=100 prometheus grafana
```

In GitLab, create a **project runner** in only the trusted test project; do not share it at group or instance scope. Restrict it to protected branches/tags and disable untagged jobs. Protect the test branch before running acceptance. On monitoring VM register it interactively so the `glrt-` token is not on a command line or in this repository:

```bash
cd /opt/platform/deploy/monitoring
sudo docker compose run --rm runner register --template-config /registration-template.toml --url "https://gitlab.internal.example.com" --executor docker --docker-image alpine:3.21
# Paste the project runner authentication token only at the prompt.
```

The registration template supplies the job limits below. Verify `/srv/monitoring/runner/config.toml` (generated locally, never commit it): set global `concurrent = 1`, the project runner's `limit = 1`, and under its `[runners.docker]` section set `privileged = false`, `services_privileged = false`, `cpus = "1"`, `memory = "2g"`, and `memory_swap = "2g"`. Do not mount the host Docker socket into CI job containers or enable privileged jobs. Then:

```bash
sudo chmod 600 /srv/monitoring/runner/config.toml
sudo docker compose up -d runner
sudo docker compose logs --tail=100 runner
```

The Runner container itself has a 0.5 CPU/512 MiB cap. Its Docker socket can control the host, so only trusted maintainers may change this project's CI configuration. Give this project runner the `bootcamp` tag. For acceptance, copy `deploy/runner-smoke.gitlab-ci.yml` to the trusted project's `.gitlab-ci.yml`. It checks repository checkout and job execution, confirms the host Docker socket is absent from the job, and uploads a result artifact. Confirm the job passes on this runner and the artifact is downloadable. The smoke job also asserts the actual cgroup limits are one CPU and 2 GiB and that the SYS_ADMIN capability is absent. Verify the Runner configuration still has `concurrent = 1`, `limit = 1`, and `privileged = false`.

Record the pipeline/job result, checked commit, and verified artifact in private operator evidence. Runner registration or online status alone is not acceptance.

## 6. Schedule backups and verify

Install schedules using root-owned `/etc/cron.d/bootcamp-gitlab-backup` and `/etc/cron.d/bootcamp-grafana-backup`, with mode `644`. Set both hosts to `Etc/UTC` and enable cron so the schedules below use UTC. To install or replace a schedule, use `sudoedit` on the corresponding file and retain a trailing newline. Do not also add a duplicate root crontab entry.

GitLab VM:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 2 * * * root BACKUP_ACCOUNT=YOUR_STORAGE_ACCOUNT BACKUP_CLIENT_ID=YOUR_GITLAB_IDENTITY_CLIENT_ID /opt/platform/scripts/backup-gitlab.sh >> /var/log/gitlab-backup.log 2>&1
```

Monitoring VM:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root BACKUP_ACCOUNT=YOUR_STORAGE_ACCOUNT BACKUP_CLIENT_ID=YOUR_MONITORING_IDENTITY_CLIENT_ID /opt/platform/scripts/backup-grafana.sh >> /var/log/grafana-backup.log 2>&1
```

On each host run `sudo timedatectl set-timezone Etc/UTC`, `sudo systemctl enable --now cron`, and check `timedatectl show -p Timezone`.

Check each morning after the job: `sudo cat /srv/gitlab/backup-status/last-success` or `sudo cat /srv/monitoring/backups/last-success`, inspect the corresponding log, and list recent Blob objects with `az storage blob list --auth-mode login --account-name YOUR_STORAGE_ACCOUNT --container-name platform-backups --prefix gitlab/` or `--prefix grafana/`. Check both the GitLab application archive and config archive for the same run. A script error means no success marker update; fix space, identity, or upload failures before relying on that day's backup. Repeat a complete restore test for each major GitLab upgrade.

## Acceptance checks

| Check | Command or observation |
| --- | --- |
| Terraform | `fmt`, `validate`, reviewed plan without VM replacement; 4 total vCPUs |
| VPN HTTPS | VPN-connected client opens `https://<hostname>/` with trusted TLS, signs in with GitLab local account |
| Git over HTTPS | Clone the test project, commit, and push; verify commit appears in GitLab |
| Runner | Project runner executes the smoke job; download and verify its artifact; actual cgroup CPU/memory limits pass and host Docker socket/SYS_ADMIN are absent |
| Prometheus | On monitoring VM: `curl -s http://127.0.0.1:9090/api/v1/targets`; self, local Node Exporter, and GitLab Node Exporter report **UP** |
| Grafana | VPN client signs in at `http://10.0.3.10:3000`; Prometheus data source works |
| Backups | Both GitLab objects and daily Grafana objects appear in Blob; latest success markers are current |
| Restore | Initial full restore on empty monitoring VM verified against the test repository and database |
