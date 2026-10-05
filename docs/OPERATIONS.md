<p align="center"><img src="assets/cloudsphere-logo.png" alt="cloudSphere logo" width="150"></p>

# Operate cloudSphere

Use this guide after installation and acceptance. Commands run in Bash on the named VM through an administrator VPN connection. Examples assume `/opt/platform` and administrator `azureadmin`; supply your actual hostname, storage account, and identity client IDs. Keep those values and verification records privately.

## Service checks

GitLab VM (`10.0.1.10`):

```bash
findmnt /srv/gitlab
cd /opt/platform/deploy/gitlab
sudo docker compose ps
sudo docker compose logs --tail=100 gitlab
sudo docker exec gitlab gitlab-ctl status
```

Monitoring VM (`10.0.3.10`):

```bash
findmnt /srv/monitoring
cd /opt/platform/deploy/monitoring
sudo docker compose ps
sudo docker compose logs --tail=100 prometheus grafana runner
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

All three configured Prometheus targets should be UP. Open Grafana at `http://10.0.3.10:3000` through the VPN and check its Prometheus data source. Create or import dashboards appropriate to your hosts; dashboards and alert notifications are not provisioned by this repository. Node Exporter health does not establish that GitLab login, repositories, or CI work.

After a restart or maintenance, check trusted GitLab HTTPS from a VPN client, clone/push to the test project, and execute the Runner smoke pipeline with a downloadable artifact. Use the [deployment acceptance checklist](DEPLOYMENT_PLAN.md#acceptance-checks).

## Daily backups

Schedules are installed in the [deployment guide](DEPLOYMENT_PLAN.md#6-schedule-backups-and-verify): GitLab at 02:00 UTC and Grafana at 03:00 UTC. Run a backup manually on the corresponding VM with your identity values:

```bash
# GitLab VM
sudo env BACKUP_ACCOUNT="YOUR_STORAGE_ACCOUNT" BACKUP_CLIENT_ID="YOUR_GITLAB_IDENTITY_CLIENT_ID" /opt/platform/scripts/backup-gitlab.sh

# Monitoring VM
sudo env BACKUP_ACCOUNT="YOUR_STORAGE_ACCOUNT" BACKUP_CLIENT_ID="YOUR_MONITORING_IDENTITY_CLIENT_ID" /opt/platform/scripts/backup-grafana.sh
```

Only repository packing is incremental. Sunday uses full packing; other days use the last successfully uploaded local archive when available. An absent local predecessor forces a full backup. Each application archive is a complete restore point, requiring its matching configuration/secrets archive.

Check each morning on the relevant host:

```bash
# GitLab VM
sudo cat /srv/gitlab/backup-status/last-success
sudo tail -n 50 /var/log/gitlab-backup.log

# Monitoring VM
sudo cat /srv/monitoring/backups/last-success
sudo tail -n 50 /var/log/grafana-backup.log
```

Confirm the timestamp is current and list the uploaded objects from either VM using its identity:

```bash
az login --identity --client-id "YOUR_THIS_VM_IDENTITY_CLIENT_ID"
az storage blob list --auth-mode login --account-name YOUR_STORAGE_ACCOUNT --container-name platform-backups --prefix gitlab/ --output table
az storage blob list --auth-mode login --account-name YOUR_STORAGE_ACCOUNT --container-name platform-backups --prefix grafana/ --output table
```

For GitLab, the application tar and matching configuration tar must both exist for the same backup ID. For Grafana, the database and configuration archive must share the same timestamp. A local success marker is updated atomically only after both uploads succeed. An object listing is not a restore test; follow the [recovery guide](runbooks/RESTORE.md).

If a backup fails:

1. Inspect its log, free space, data mount, authenticated Blob permissions, and actual outbound connectivity.
2. Check whether only one object uploaded. Treat that run as incomplete until its matching object is available and verified.
3. Fix the cause and rerun the script to make a new restore point. The script does not automatically retry uploads or resume an incomplete pair.
4. Keep the recorded last successful GitLab archive. Failed runs can leave files; inspect them before removing any, and do not use them as incremental predecessors.

Do not edit a success marker to make a failed backup appear successful. Missing success records make the next GitLab run full; a malformed record stops it for inspection. Daily failures increase the potential data-loss window beyond 24 hours.

## Disk and log maintenance

On both VMs:

```bash
df -h / /srv/gitlab  # GitLab VM
df -h / /srv/monitoring  # Monitoring VM
sudo docker system df
```

Run only the line for the current host. Data disks hold application state. Docker images, job layers, and cache volumes still consume the OS disk; the monitoring VM's OS disk is 32 GiB.

Compose service stdout/stderr logs rotate at 10 MiB per file, with three files retained per container. This does not limit GitLab's internal logs, CI job-container logs, backup cron logs, images, or caches. Keep enough free space for backups and upgrades. Review host log retention and cache growth during maintenance.

Inspect unused images with `sudo docker image ls` before considering `sudo docker image prune` for dangling images. Retain the exact GitLab image versions needed by backups. Do not run volume pruning or broad cleanup against application data. Never format a populated data disk.

## HTTPS renewal

The current installation uses an operator-supplied certificate and manual renewal. Record the issuer, expiry, and renewal method privately. A publicly trusted certificate avoids installing private CA trust on user devices; private endpoints can use DNS validation. Automatic DNS renewal needs a separately prepared issuer/DNS integration and is not implemented here.

Renew through the issuer, securely install the full chain and private key at `/srv/gitlab/config/ssl/<hostname>.crt` and `.key`, restrict the key to root with mode `600`, then:

```bash
sudo docker exec gitlab gitlab-ctl hup nginx
```

Verify the served certificate from a VPN client and confirm Git and Runner access. Keep the prior material securely until verification is complete. Do not publish certificate files, issuer credentials, or DNS challenge records.

## Updates and upgrades

Image versions are pinned for reproducibility, not a promise of ongoing support. Review the products' release notes and GitLab's [required upgrade stops](https://docs.gitlab.com/update/upgrade_paths/) before changing versions. Do not replace pinned tags with `latest`.

1. Choose a maintenance window. Record the installed image versions and verify a current, matching backup pair.
2. Prepare and validate version changes in the repository. Keep Compose, the SAD, and restore commands consistent. Check actual egress before pulling images.
3. Obtain deployment authorization before changing hosts or services. On the appropriate host, verify its data mount, validate Compose, then pull and start the reviewed service version.
4. Verify application access, clone/push, the real CI job/artifact, monitoring, and fresh backup uploads. A failed upgrade may require restoring pre-upgrade data with its exact old version; changing only the image tag is not a reliable rollback.
5. Repeat a full GitLab restore verification for major upgrades. The monitoring VM is no longer empty: prepare an explicit drill arrangement with downtime and preserved data, within the four-vCPU limit, before proceeding. Do not reuse the initial drill commands against installed monitoring services.

## Access administration

Use [VPN administration](VPN.md) for assignment, supported clients, and removal. Keep VPN and GitLab access records together privately, but manage their permissions separately. Test unassigned-user denial before rollout. Do not distribute administrator SSH keys to developers.

[Deployment](DEPLOYMENT_PLAN.md) · [Recovery](runbooks/RESTORE.md) · [Back to cloudSphere](../README.md)
