#!/usr/bin/env bash
# Scenario: "the VM is down". Deallocates the web VM; run with "start" to bring it back.
#   scripts/fault-vm-stop.sh        # stop
#   scripts/fault-vm-stop.sh start  # restore
source "$(dirname "$0")/common.sh"
if [ "${1:-stop}" = "start" ]; then
  az vm start -g "$RG" -n "$WEB_VM" -o none && echo "$WEB_VM started"
else
  az vm deallocate -g "$RG" -n "$WEB_VM" -o none && echo "$WEB_VM deallocated at $(date -u +%H:%M) UTC"
fi
