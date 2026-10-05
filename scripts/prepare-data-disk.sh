#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: sudo $0 <gitlab|monitoring> <disk-by-id-path>" >&2; exit 2; }
[[ $# -eq 2 ]] || usage
case "$1" in
  gitlab) mount_point=/srv/gitlab; expected_gib=128 ;;
  monitoring) mount_point=/srv/monitoring; expected_gib=64 ;;
  *) usage ;;
esac
[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
disk=$(readlink -f -- "$2")
[[ -b "$disk" ]] || { echo "Not a block device: $2" >&2; exit 1; }
[[ "$2" == /dev/disk/by-id/* ]] || { echo 'Use a stable /dev/disk/by-id path' >&2; exit 1; }
[[ "$(lsblk -dn -o TYPE "$disk")" == disk ]] || { echo 'Pass a whole disk, not a partition' >&2; exit 1; }
size=$(blockdev --getsize64 "$disk")
(( size >= expected_gib * 1024 * 1024 * 1024 )) || { echo 'Disk smaller than expected; refusing' >&2; exit 1; }
already_mounted=false
if findmnt -rn "$mount_point" >/dev/null; then
  echo "$mount_point is already mounted; checking filesystem"
  [[ $(findmnt -nro SOURCE "$mount_point" | xargs readlink -f) == "$disk" ]] || { echo 'Another disk is mounted here' >&2; exit 1; }
  already_mounted=true
fi
if [[ "$already_mounted" == false && -n $(find "$mount_point" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
  echo 'Mount directory contains files; refusing to hide them' >&2; exit 1
fi
fs_type=$(blkid -s TYPE -o value "$disk" || true)
if [[ -z "$fs_type" ]]; then
  if lsblk -nr -o NAME "$disk" | tail -n +2 | grep -q . || wipefs -n "$disk" | grep -q .; then
    echo 'Disk contains partitions or signatures; refusing to format' >&2; exit 1
  fi
  # A new Azure Empty disk reads as all zeroes. Check the entire disk before mkfs.
  cmp -s -n "$size" "$disk" /dev/zero || { echo 'Disk contains nonzero data; refusing to format' >&2; exit 1; }
  mkfs.ext4 -F "$disk"
  fs_type=ext4
fi
[[ "$fs_type" == ext4 ]] || { echo "Expected ext4, found $fs_type" >&2; exit 1; }
uuid=$(blkid -s UUID -o value "$disk")
mkdir -p "$mount_point"
if ! grep -q "^UUID=$uuid[[:space:]]" /etc/fstab; then
  if grep -q "[[:space:]]$mount_point[[:space:]]" /etc/fstab; then
    echo 'Different fstab entry exists for mount point; refusing' >&2; exit 1
  fi
  printf 'UUID=%s %s ext4 defaults 0 2\n' "$uuid" "$mount_point" >> /etc/fstab
  systemctl daemon-reload
fi
mountpoint -q "$mount_point" || mount "$mount_point"
findmnt "$mount_point"
if [[ $1 == gitlab ]]; then
  mkdir -p "$mount_point"/{config,logs,data}
else
  mkdir -p "$mount_point"/{prometheus,grafana,runner,secrets,backups}
  chown 65534:65534 "$mount_point/prometheus"
  chown 472:472 "$mount_point/grafana"
  chmod 700 "$mount_point"/{runner,secrets,backups}
fi
