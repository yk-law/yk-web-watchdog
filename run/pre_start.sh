#!/usr/bin/env bash
# Mark restart when the service is started manually (systemctl start), not by the timer.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="yk-web-watchdog"

set -a
# shellcheck disable=SC1091
source "$BASE_DIR/.env"
set +a

FLAG_FILE="${RESTART_FLAG_FILE:-$BASE_DIR/.restart_requested}"

# Timer-triggered runs list the timer in Activators; manual systemctl start does not.
ACTIVATORS=$(systemctl show -p Activators --value "${SERVICE_NAME}.service" 2>/dev/null || true)
if [ -z "$ACTIVATORS" ]; then
    touch "$FLAG_FILE"
fi
