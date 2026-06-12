#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="yk-web-watchdog"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

if [ ! -f "$BASE_DIR/.env" ]; then
    echo "ERROR: $BASE_DIR/.env not found."
    echo "Copy .env.example and set SLACK_WEBHOOK_URL (and paths) first:"
    echo "  cp $BASE_DIR/.env.example $BASE_DIR/.env"
    exit 1
fi

if [ ! -x "$BASE_DIR/run/run.sh" ] || [ ! -x "$BASE_DIR/run/pre_start.sh" ]; then
    echo "ERROR: $BASE_DIR/run/run.sh or run/pre_start.sh missing or not executable."
    echo "  chmod +x $BASE_DIR/run/*.sh"
    exit 1
fi

echo "Installing systemd units for:"
echo "  BASE_DIR=$BASE_DIR"
echo "  USER=$USER"

# service
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=YK Web Watchdog - website healthcheck runner
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$BASE_DIR
EnvironmentFile=$BASE_DIR/.env
ExecStartPre=$BASE_DIR/run/pre_start.sh
ExecStart=$BASE_DIR/run/run.sh

NoNewPrivileges=true
PrivateTmp=true
EOF

# timer (every 3 minutes at exact clock time)
sudo tee "$TIMER_FILE" >/dev/null <<EOF
[Unit]
Description=Run YK Web Watchdog every 3 minutes (aligned)

[Timer]
# ✅ 즉시 1회 실행 (설치 직후)
OnBootSec=5s

# ✅ 정각 기준 3분마다 실행
OnCalendar=*:0/3

# 서버 재부팅 후 missed 실행 보정
Persistent=true

# 정각 정확도
AccuracySec=1s

Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload

echo "Installed: $SERVICE_FILE"
echo "Installed: $TIMER_FILE"
echo "Now run: ./run/start.sh"

