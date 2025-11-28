#!/usr/bin/env bash
set -euo pipefail

# log_analyzer.sh - simple nginx access.log status code counter
# Usage:
#   ./log_analyzer.sh /path/to/access.log [--report-dir /path/to/reports]

LOGFILE=${1:-/var/log/nginx/access.log}
REPORT_DIR="/var/log/log-analyzer"   # default report dir
# allow optional --report-dir <dir>
if [[ "${2:-}" == "--report-dir" && -n "${3:-}" ]]; then
  REPORT_DIR="$3"
fi

# Safety checks
if [[ ! -f "$LOGFILE" ]]; then
  echo "Error: logfile '$LOGFILE' does not exist." >&2
  exit 2
fi

mkdir -p "$REPORT_DIR" 2>/dev/null || true

# Helper: extract status code from a single log line robustly.
# This sed command matches the pattern: " ... " <status> <bytes>
# It captures 3-digit status codes (100-599).
extract_status() {
  sed -E 's/.*" ([0-9]{3}) .*/\1/'
}

# Build report
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
REPORT_FILE="${REPORT_DIR}/log-report-${TIMESTAMP}.txt"

{
  echo "Log Analyzer Report"
  echo "Log file: $LOGFILE"
  echo "Generated: $(date --rfc-3339=seconds)"
  echo "----------------------------------------"
  echo "Top status code counts:"
  # Extract status codes and count them
  # We use awk -> sed fallback if field position changes:
  # 1) Try simple awk for common combined log ("status is 9th field")
  # 2) If that produces non-digit results, fallback to sed extraction
  STATUS_LIST=$(awk '{print $9}' "$LOGFILE" | grep -E '^[0-9]{3}$' || true)
  if [[ -z "$STATUS_LIST" ]]; then
    # fallback to sed extraction
    STATUS_LIST=$(cat "$LOGFILE" | extract_status)
  fi

  # Print counts sorted
  printf "%s\n" "$STATUS_LIST" | sort | uniq -c | sort -rn | awk '{printf "%s -> %s\n", $2, $1}'

  echo "----------------------------------------"
  # Focus on common codes 200 and 404 (and show counts)
  count_code() {
    local code=$1
    # if status list empty it will return 0
    printf "%s" "$STATUS_LIST" | grep -E "^${code}$" -c || echo 0
  }

  echo "200 count: $(count_code 200)"
  echo "404 count: $(count_code 404)"
  echo "----------------------------------------"
  echo "Top 10 requested URIs (by frequency):"
  # Try to extract the request path (between the quotes)
  # Typical log: ... "GET /path HTTP/1.1" 200 ...
  awk -F\" '{print $2}' "$LOGFILE" | awk '{print $2}' | sort | grep -v '^$' | uniq -c | sort -rn | head -n 10 | awk '{printf "%s\t%s\n", $2, $1}'

  echo "----------------------------------------"
  echo "Notes:"
  echo "- Script assumes NGINX combined log format or common variants."
  echo "- If your log uses a different format, adapt the extract rules."
} > "$REPORT_FILE"

# Show short summary to stdout
echo "Report saved to: $REPORT_FILE"
echo "Summary (top 5 status codes):"
head -n 20 "$REPORT_FILE" | sed -n '1,20p'
