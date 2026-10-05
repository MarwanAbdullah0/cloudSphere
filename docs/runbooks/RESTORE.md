<p align="center"><img src="../assets/cloudsphere-logo.png" alt="cloudSphere logo" width="150"></p>

# Recover cloudSphere

## Disaster recovery approach

Recovery is manual: repair or rebuild the affected host, then restore its persistent state from Blob. There is no standby VM or automatic failover. The monitoring VM is used for the initial restore test while it is empty; it is not a permanent GitLab standby.

| Item | Recovery source |
| --- | --- |
| GitLab application data | Latest successful GitLab application archive in Blob |
| GitLab secrets, configuration, TLS | Matching configuration archive from the same backup run |
| Grafana dashboards, users, settings | Matching Grafana database and configuration backup |
| Prometheus | Reinstall from repository configuration; start collecting fresh metrics |
| Runner | Reinstall from repository configuration and register again with the trusted project |
| Azure infrastructure | Terraform configuration plus securely retained state; inspect existing resources before applying |

**Data-loss target (RPO):** about 24 hours with successful daily backups. A missed or failed backup extends that window. **Recovery time (RTO):** measure archive download, initialization, restore, and verification during your drill. Record separately whether host provisioning is included; no duration is guaranteed by this reference configuration. The Blob account uses LRS in the same Azure region, so this design covers recoverable host/disk failures and supported deletion recovery, not a complete regional outage.

For an incident:

1. Identify whether the problem is the service, OS, data disk, or VM. Record the failure and stop normal writes before restoring application data.
2. Check the latest successful Blob archive and its matching configuration archive. Verify the GitLab CE version that produced the archive.
3. If the data disk is intact, repair/reinstall the service using that disk before deciding that a backup restore is necessary. Never format a populated disk.
4. If data is lost, prepare an empty recovery destination. Reuse or repair the existing VM where possible. If replacing a failed VM, remove its compute allocation before creating a replacement so the project remains within four vCPUs.
5. Restore GitLab with its matching secrets and exact CE version using the procedure below. Restore Grafana if needed; reinstall Prometheus and re-register the project Runner.
6. Verify GitLab sign-in, a known repository and commit, clone/push, a Runner job, Grafana access, and Prometheus targets UP.
7. Resume access and scheduled backups. Record the restore point used, any data lost, recovery duration, and the checks performed. Update the SAD and this runbook if the recovery procedure changed.

## Initial complete GitLab restore test on the empty monitoring VM

Do this **after the first GitLab backup upload and before installing monitoring services**. The temporary restore needs enough free space on `/srv/monitoring` for the archive, unpacked data, and GitLab working files; check with `df -h` and stop for a reviewed capacity decision if the 64-GiB disk is insufficient. The source and restore image must be exactly `gitlab/gitlab-ce:18.6.4-ce.0` (or the exact version used when the backup was created). The GitLab backup tar is a complete restore point even when repository packing used incremental mode. Use the matching configuration/secrets archive from the same run.

On the monitoring VM, set the archive and config object names using the `last-success` record or `az storage blob list`. Example commands, replacing all `YOUR_...` values and the example hostname:

```bash
umask 077
export BACKUP_ACCOUNT="YOUR_STORAGE_ACCOUNT"
export BACKUP_CLIENT_ID="YOUR_MONITORING_IDENTITY_CLIENT_ID"
export BACKUP_TAR="YOUR_BACKUP_ID_gitlab_backup.tar"
export CONFIG_TAR="YOUR_BACKUP_ID_gitlab_config.tar.gz"
export GITLAB_HOSTNAME="gitlab.internal.example.com"
# Refuse to reuse an existing restore directory or container.
mountpoint -q /srv/monitoring || exit 1
test ! -e /srv/monitoring/restore || exit 1
if sudo docker container inspect gitlab-restore >/dev/null 2>&1; then exit 1; fi
sudo mkdir -p /srv/monitoring/restore/{config,logs,data/backups}
sudo chown -R azureadmin:azureadmin /srv/monitoring/restore
sudo chmod 700 /srv/monitoring/restore
az login --identity --client-id "$BACKUP_CLIENT_ID"
az storage blob download --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name platform-backups --name "gitlab/archives/$BACKUP_TAR" --file "/srv/monitoring/restore/data/backups/$BACKUP_TAR"
az storage blob download --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name platform-backups --name "gitlab/config/$CONFIG_TAR" --file "/srv/monitoring/restore/$CONFIG_TAR"
sudo tar -C /srv/monitoring/restore -xzf "/srv/monitoring/restore/$CONFIG_TAR"
sudo docker run -d --shm-size 256m --name gitlab-restore --hostname "$GITLAB_HOSTNAME" \
  -e "GITLAB_OMNIBUS_CONFIG=external_url 'https://$GITLAB_HOSTNAME'; letsencrypt['enable'] = false; puma['worker_processes'] = 0; sidekiq['concurrency'] = 10; prometheus_monitoring['enable'] = false; prometheus['enable'] = false; alertmanager['enable'] = false; gitlab_exporter['enable'] = false; node_exporter['enable'] = false; postgres_exporter['enable'] = false; redis_exporter['enable'] = false; puma['exporter_enabled'] = false; gitlab_kas['enable'] = false; registry['enable'] = false" \
  -v /srv/monitoring/restore/config:/etc/gitlab \
  -v /srv/monitoring/restore/logs:/var/log/gitlab \
  -v /srv/monitoring/restore/data:/var/opt/gitlab \
  gitlab/gitlab-ce:18.6.4-ce.0
sudo docker logs --tail=100 gitlab-restore
sudo docker exec gitlab-restore gitlab-ctl status
```

Wait until bundled PostgreSQL, Redis/Valkey, Gitaly, Puma, and Sidekiq have initialized. The temporary container publishes no host ports. The config archive includes `gitlab-secrets.json` and TLS material; protect it as a secret. Then:

```bash
export BACKUP_ID="${BACKUP_TAR%_gitlab_backup.tar}"
sudo docker exec gitlab-restore chown git:git "/var/opt/gitlab/backups/$BACKUP_TAR"
sudo docker exec gitlab-restore gitlab-ctl stop puma
sudo docker exec gitlab-restore gitlab-ctl stop sidekiq
sudo docker exec -it gitlab-restore gitlab-backup restore "BACKUP=$BACKUP_ID"
sudo docker exec gitlab-restore gitlab-ctl reconfigure
sudo docker exec gitlab-restore gitlab-ctl restart
sudo docker exec gitlab-restore gitlab-rake gitlab:check SANITIZE=true
sudo docker exec gitlab-restore gitlab-rake gitlab:doctor:secrets
sudo docker exec gitlab-restore gitlab-rails runner 'puts Project.count'
```

The `<backup-id>` is the tar filename without `_gitlab_backup.tar`. A nonzero project count alone is insufficient. Verify the expected project exists and its repository head matches the commit recorded before the backup; a GitLab Rails console or `gitlab-rails runner` can inspect that project by full path. Record the backup ID, GitLab version, restore duration, and result outside this repository. Only then remove the temporary restore container and restore directory, and deploy the normal monitoring stack. Do not run this test against a populated GitLab instance.

After recording successful verification, reclaim the monitoring disk space:

```bash
sudo docker rm -f gitlab-restore
sudo rm -rf -- /srv/monitoring/restore
```

Keep a secure copy of Terraform state, the administrator SSH key, Entra application/tenant recovery instructions, and any legacy VPN CA private key outside Git. These operator files are not included in the GitLab/Grafana backups. Users return through Entra VPN sign-in on supported Windows/macOS clients once the network is available; VPN recovery does not recreate local application accounts.

## Later restore drills

The initial commands above require an empty monitoring VM. After monitoring installation, do not run them against its populated disk. Before a major GitLab upgrade, prepare a maintenance drill with preserved Grafana/Runner data, enough disk space, and no more than four allocated vCPUs. Record the chosen empty destination and downtime before deployment; this release does not provide a standing restore-test host. Use the exact backup version and repeat application, secrets, and known-commit verification. See [operations](../OPERATIONS.md#updates-and-upgrades).

## Actual GitLab recovery

Create a replacement GitLab installation at the **same CE version** as the chosen archive. Attach and mount an empty suitable data disk, restore the matching configuration and secrets archive to `/srv/gitlab/config`, and place the selected backup tar in `/srv/gitlab/data/backups`. Keep the `gitlab-secrets.json` from that archive. Start GitLab with the same hostname and TLS settings using the Compose file, wait for its initial database setup, stop Puma and Sidekiq, then run `sudo docker exec -it gitlab gitlab-backup restore "BACKUP=$BACKUP_ID"`. Run `gitlab-ctl reconfigure`, restart, and `gitlab-rake gitlab:check SANITIZE=true`. Validate sign-in, a known project, clone/push, and a pipeline before reopening normal use. The [GitLab restore guide](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) describes version and empty target requirements.

## Grafana recovery

On the monitoring VM, choose matching `grafana/grafana-<timestamp>.db` and `grafana/grafana-<timestamp>-config.tar.gz` objects using `az storage blob list`. Then:

```bash
umask 077
export BACKUP_ACCOUNT="YOUR_STORAGE_ACCOUNT"
export BACKUP_CLIENT_ID="YOUR_MONITORING_IDENTITY_CLIENT_ID"
export GRAFANA_BASE="grafana-YYYYMMDDTHHMMSSZ"
az login --identity --client-id "$BACKUP_CLIENT_ID"
cd /opt/platform/deploy/monitoring
sudo docker compose stop grafana
az storage blob download --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name platform-backups --name "grafana/$GRAFANA_BASE.db" --file "/tmp/$GRAFANA_BASE.db"
az storage blob download --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name platform-backups --name "grafana/$GRAFANA_BASE-config.tar.gz" --file "/tmp/$GRAFANA_BASE-config.tar.gz"
sudo rm -f /srv/monitoring/grafana/grafana.db-wal /srv/monitoring/grafana/grafana.db-shm
sudo install -o 472 -g 472 -m 600 "/tmp/$GRAFANA_BASE.db" /srv/monitoring/grafana/grafana.db
sudo tar -C /opt/platform/deploy/monitoring -xzf "/tmp/$GRAFANA_BASE-config.tar.gz"
sudo docker compose up -d grafana
```

Verify the local login and Prometheus data source, then remove the two downloaded files from `/tmp`. The restored database retains its previous Grafana password. Keep that password securely; recreating the admin password file alone does not reset an existing database login. If it was lost, reset the administrator password with Grafana CLI. The file in `/srv/monitoring/secrets` is local secret material; recreate it securely if the disk was lost, with owner `472:472` and mode `600`. Prometheus's seven-day metrics are not restored.

After recovery, run fresh backups and verify their matching uploads before returning to the daily schedule. If the recorded successful local GitLab archive is missing, the next run uses full packing. Keep failed restore evidence privately.

[Operations](../OPERATIONS.md) · [Deployment](../DEPLOYMENT_PLAN.md) · [Architecture](../SOLUTION_ARCHITECTURE.md)
