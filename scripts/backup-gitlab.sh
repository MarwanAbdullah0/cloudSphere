#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${BACKUP_ACCOUNT:?Set BACKUP_ACCOUNT to the Azure Storage account name}"
: "${BACKUP_CLIENT_ID:?Set BACKUP_CLIENT_ID to this VM backup identity client ID}"
export AZURE_CONFIG_DIR
AZURE_CONFIG_DIR=$(mktemp -d /tmp/gitlab-backup-azure.XXXXXXXX)
trap 'rm -rf -- "$AZURE_CONFIG_DIR"' EXIT
container=platform-backups
backup_dir=/srv/gitlab/data/backups
status_dir=/srv/gitlab/backup-status
mountpoint -q /srv/gitlab || { echo 'GitLab data disk is not mounted' >&2; exit 1; }
mkdir -p "$backup_dir" "$status_dir"
exec 9>"$status_dir/lock"
flock -n 9 || { echo 'Backup already running' >&2; exit 1; }
previous=$(find "$backup_dir" -maxdepth 1 -name '*_gitlab_backup.tar' -printf '%T@ %f\n' | sort -nr | head -1 | cut -d' ' -f2-)
previous_id=${previous%_gitlab_backup.tar}
free_bytes=$(df -B1 --output=avail "$backup_dir" | tail -1)
previous_bytes=0
[[ -z "$previous" ]] || previous_bytes=$(stat -c %s "$backup_dir/$previous")
required_bytes=$((previous_bytes * 2 + 8 * 1024 * 1024 * 1024))
(( free_bytes > required_bytes )) || { echo "Insufficient free disk space: need >$required_bytes bytes" >&2; exit 1; }
args=(gitlab-backup create)
# UTC Sunday: full backup. An absent predecessor also forces a full backup.
if [[ $(date -u +%u) != 7 && -n "$previous" ]]; then
  args+=(INCREMENTAL=yes "PREVIOUS_BACKUP=$previous_id")
fi
docker exec gitlab "${args[@]}"
current=$(find "$backup_dir" -maxdepth 1 -name '*_gitlab_backup.tar' -printf '%T@ %f\n' | sort -nr | head -1 | cut -d' ' -f2-)
[[ -n "$current" && "$current" != "$previous" ]] || { echo 'No new backup archive found' >&2; exit 1; }
archive="$backup_dir/$current"
[[ -s "$archive" ]] || { echo 'Backup archive is empty' >&2; exit 1; }
config_archive="$status_dir/${current%_gitlab_backup.tar}_gitlab_config.tar.gz"
tar -C /srv/gitlab -czf "$config_archive" config
az login --identity --client-id "$BACKUP_CLIENT_ID" --output none
az storage blob upload --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name "$container" --name "gitlab/archives/$current" --file "$archive" --overwrite false --output none
az storage blob upload --auth-mode login --account-name "$BACKUP_ACCOUNT" --container-name "$container" --name "gitlab/config/$(basename "$config_archive")" --file "$config_archive" --overwrite false --output none
printf '%s %s\n' "$(date -u +%FT%TZ)" "$current" > "$status_dir/last-success"
find "$backup_dir" -maxdepth 1 -name '*_gitlab_backup.tar' ! -name "$current" -delete
rm -f -- "$config_archive"
echo "Uploaded GitLab archive and config: $current"
