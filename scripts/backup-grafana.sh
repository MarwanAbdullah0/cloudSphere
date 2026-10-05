#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${BACKUP_ACCOUNT:?Set BACKUP_ACCOUNT to the Azure Storage account name}"
: "${BACKUP_CLIENT_ID:?Set BACKUP_CLIENT_ID to this VM backup identity client ID}"
export AZURE_CONFIG_DIR
AZURE_CONFIG_DIR=$(mktemp -d /tmp/grafana-backup-azure.XXXXXXXX)
trap 'rm -rf -- "$AZURE_CONFIG_DIR"' EXIT
mountpoint -q /srv/monitoring || { echo 'Monitoring data disk is not mounted' >&2; exit 1; }
work=/srv/monitoring/backups
mkdir -p "$work"
exec 9>"$work/lock"
flock -n 9 || { echo 'Backup already running' >&2; exit 1; }
[[ -f /srv/monitoring/grafana/grafana.db ]] || { echo 'Grafana database missing' >&2; exit 1; }
free_bytes=$(df -B1 --output=avail "$work" | tail -1)
db_bytes=$(stat -c %s /srv/monitoring/grafana/grafana.db)
(( free_bytes > db_bytes * 2 + 100 * 1024 * 1024 )) || { echo 'Insufficient free disk space for Grafana backup' >&2; exit 1; }
base="grafana-$(date -u +%Y%m%dT%H%M%SZ)"
sqlite3 /srv/monitoring/grafana/grafana.db ".backup '$work/$base.db'"
tar -C /opt/platform/deploy/monitoring -czf "$work/$base-config.tar.gz" grafana-provisioning compose.yaml prometheus.yml
az login --identity --client-id "$BACKUP_CLIENT_ID" --output none
for file in "$work/$base.db" "$work/$base-config.tar.gz"; do
  az storage blob upload --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name platform-backups --name "grafana/$(basename "$file")" --file "$file" --overwrite false --output none
done
success_record=$(mktemp "$work/last-success.XXXXXXXX")
printf '%s %s\n' "$(date -u +%FT%TZ)" "$base" > "$success_record"
mv -f -- "$success_record" "$work/last-success"
rm -f -- "$work/$base.db" "$work/$base-config.tar.gz"
echo "Uploaded Grafana backup: $base"
