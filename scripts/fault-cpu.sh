#!/usr/bin/env bash
# Scenario: "the VM was slow". Loads every CPU of the web VM for 15 minutes (default), in the background.
#   scripts/fault-cpu.sh [minutes]
source "$(dirname "$0")/common.sh"
MIN=${1:-15}
echo "CPU load on $WEB_VM for $MIN minutes, started $(date -u +%H:%M) UTC"
run_on "$WEB_VM" "nohup stress-ng --cpu 0 --timeout ${MIN}m >/dev/null 2>&1 & echo started"
