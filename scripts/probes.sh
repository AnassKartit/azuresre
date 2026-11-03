#!/usr/bin/env bash
# What the cli VM saw in the last 30 minutes: SMTP 587 and 25, and the web app (from Log Analytics).
# Use it to confirm a fault is really visible before you ask the agent.
source "$(dirname "$0")/common.sh"
WS=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)
az monitor log-analytics query -w "$WS" -o table --analytics-query "
Syslog
| where TimeGenerated > ago(30m) and ProcessName == 'lab-probe'
| summarize last_seen = max(TimeGenerated) by SyslogMessage
| order by last_seen desc"
