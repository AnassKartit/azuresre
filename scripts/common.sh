#!/usr/bin/env bash
# Shared helpers: read names from terraform outputs (run the scripts from the repo root).
set -euo pipefail

out() { terraform output -raw "$1"; }

RG=$(out resource_group)
WEB_VM=$(out web_vm)
CLI_VM=$(out cli_vm)
LAW=$(out log_analytics_workspace)

run_on() {  # run_on <vm> <shell script>
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv
}
