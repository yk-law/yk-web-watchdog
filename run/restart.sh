#!/usr/bin/env bash
set -euo pipefail
SERVICE_NAME="yk-web-watchdog"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

set -a
# shellcheck disable=SC1091
source "$BASE_DIR/.env"
set +a

STATE_FILE="${STATE_FILE:-$BASE_DIR/state.json}"
FLAG_FILE="${RESTART_FLAG_FILE:-$BASE_DIR/.restart_requested}"
WAIT_MAX_SEC="${RESTART_WAIT_MAX_SEC:-120}"

service_active_state() {
    systemctl show -p ActiveState --value "${SERVICE_NAME}.service" 2>/dev/null || echo inactive
}

wait_service_idle() {
    local deadline=$((SECONDS + WAIT_MAX_SEC))
    local state
    while true; do
        state="$(service_active_state)"
        if [ "$state" != "activating" ] && [ "$state" != "active" ]; then
            return 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: ${SERVICE_NAME}.service still ${state} after ${WAIT_MAX_SEC}s" >&2
            return 1
        fi
        sleep 1
    done
}

set_force_restart_report() {
    python3 << EOF
import json
import os

state_file = "${STATE_FILE}"
state = {}
if os.path.exists(state_file):
    with open(state_file, "r", encoding="utf-8") as f:
        state = json.load(f)

if "_global" not in state or not isinstance(state.get("_global"), dict):
    state["_global"] = {}

state["_global"]["force_restart_report"] = True

parent = os.path.dirname(os.path.abspath(state_file))
if parent:
    os.makedirs(parent, exist_ok=True)

with open(state_file, "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
EOF
}

echo "Stopping timer (avoid 3-min schedule overlap)..."
sudo systemctl stop "${SERVICE_NAME}.timer" || true

echo "Waiting for in-flight ${SERVICE_NAME}.service (max ${WAIT_MAX_SEC}s)..."
wait_service_idle

touch "$FLAG_FILE"

echo "Setting force_restart_report in: $STATE_FILE"
set_force_restart_report

echo "Starting service (dedicated restart run)..."
sudo systemctl start "${SERVICE_NAME}.service"

echo "Waiting for restart run to finish..."
wait_service_idle

echo "Re-enabling timer..."
sudo systemctl start "${SERVICE_NAME}.timer"

echo ""
echo "=== Service (last run) ==="
systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -20 || true

echo ""
echo "=== Timer ==="
systemctl status "${SERVICE_NAME}.timer" --no-pager

LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
TODAY="$(date +%F)"
LOGFILE="${LOG_DIR}/${TODAY}.log"
if [ -f "$LOGFILE" ]; then
    echo ""
    echo "=== Last log lines ($LOGFILE) ==="
    grep -E 'notify=|restart_|slack=|force_restart' "$LOGFILE" | tail -12 || true
fi
