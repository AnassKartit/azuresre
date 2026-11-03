#!/usr/bin/env bash
# Scenario: "the disk is slow". Random reads on the web VM's P1 data disk (120 IOPS) for 15 minutes
# (default), far above its limit, so Azure throttles it. Read-only: nothing is written to the disk.
#   scripts/fault-disk.sh [minutes]
source "$(dirname "$0")/common.sh"
MIN=${1:-15}
echo "Disk load on $WEB_VM data disk (LUN 0) for $MIN minutes, started $(date -u +%H:%M) UTC"
run_on "$WEB_VM" "DEV=\$(readlink -f /dev/disk/azure/scsi1/lun0 2>/dev/null || echo /dev/sdc); \
nohup fio --name=iops --filename=\$DEV --readonly --rw=randread --bs=4k --iodepth=64 --direct=1 \
--ioengine=libaio --time_based --runtime=$((MIN*60)) >/dev/null 2>&1 & echo started on \$DEV"
