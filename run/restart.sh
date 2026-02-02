#!/usr/bin/env bash
set -euo pipefail
SERVICE_NAME="yk-web-watchdog"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Set restart flag in state.json to trigger restart report
STATE_FILE="${BASE_DIR}/state.json"
if [ -f "$STATE_FILE" ]; then
    # Use python to safely update JSON
    python3 << EOF
import json
import os

state_file = "${STATE_FILE}"
if os.path.exists(state_file):
    with open(state_file, 'r', encoding='utf-8') as f:
        state = json.load(f)
    
    if '_global' not in state:
        state['_global'] = {}
    
    state['_global']['force_restart_report'] = True
    
    with open(state_file, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
EOF
fi

sudo systemctl restart "${SERVICE_NAME}.timer"
sudo systemctl start "${SERVICE_NAME}.service"
sudo systemctl status "${SERVICE_NAME}.timer" --no-pager

