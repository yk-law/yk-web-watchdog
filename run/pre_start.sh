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
TIMER_UNIT="${SERVICE_NAME}.timer"

# Only flag manual starts (systemctl start / ./run/restart.sh).
# Timer runs set TriggeredBy/InvokedBy to the timer unit; Activators is static and unreliable here.
triggered_by_timer() {
    local triggered invoked
    triggered=$(systemctl show -p TriggeredBy --value "${SERVICE_NAME}.service" 2>/dev/null || true)
    invoked=$(systemctl show -p InvokedBy --value "${SERVICE_NAME}.service" 2>/dev/null || true)
    case "$triggered|$invoked" in
        *"${TIMER_UNIT}"*) return 0 ;;
    esac
    return 1
}

if triggered_by_timer; then
    exit 0
fi

touch "$FLAG_FILE"
