#!/usr/bin/env bash
# Run an LQL query from a YAML file against live data. Handy for tight
# edit-test loops without touching the saved query store.
#
#   ./run-local-query.sh path/to/query.yaml                 # last 24h
#   ./run-local-query.sh path/to/query.yaml "-7d"           # last 7 days
#   ./run-local-query.sh path/to/query.yaml "-24h" csv      # csv output

set -euo pipefail

QUERY_FILE="${1:?usage: $0 <query.yaml> [start] [format]}"
START="${2:--24h}"
FORMAT="${3:-json}"

case "$FORMAT" in
  json) lacework query run -f "$QUERY_FILE" --start "$START" --json ;;
  csv)  lacework query run -f "$QUERY_FILE" --start "$START" --json | jq -r '(.[0] | keys_unsorted) as $k | $k, (.[] | [.[$k[]]]) | @csv' ;;
  table) lacework query run -f "$QUERY_FILE" --start "$START" ;;
  *) echo "unknown format: $FORMAT (json|csv|table)" >&2; exit 1 ;;
esac
