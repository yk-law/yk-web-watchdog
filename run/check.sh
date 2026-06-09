#!/usr/bin/env bash
# Quick check script for yk-web-watchdog status

SERVICE_NAME="yk-web-watchdog"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "🔍 YK Web Watchdog Status Check"
echo "=================================="
echo ""

# Deployment sanity (common failure: moved dir or missing .env)
echo "🛠️  Deployment:"
DEPLOY_OK=true

if [ -f "$BASE_DIR/.env" ]; then
    echo "   ✅ .env exists: $BASE_DIR/.env"
else
    echo "   ❌ .env missing: $BASE_DIR/.env"
    echo "      → cp .env.example .env  후 SLACK_WEBHOOK_URL 등 설정"
    DEPLOY_OK=false
fi

if [ -x "$BASE_DIR/run/run.sh" ]; then
    echo "   ✅ run.sh executable: $BASE_DIR/run/run.sh"
else
    echo "   ❌ run/run.sh missing or not executable"
    DEPLOY_OK=false
fi

if command -v systemctl &>/dev/null && systemctl cat "${SERVICE_NAME}.service" &>/dev/null; then
    UNIT_DIR=$(systemctl show -p WorkingDirectory --value "${SERVICE_NAME}.service" 2>/dev/null || true)
    UNIT_ENV=$(systemctl show -p EnvironmentFiles --value "${SERVICE_NAME}.service" 2>/dev/null | awk '{print $1}' || true)
    UNIT_EXEC=$(systemctl show -p ExecStart --value "${SERVICE_NAME}.service" 2>/dev/null | awk '{print $2}' || true)

    if [ "$UNIT_DIR" = "$BASE_DIR" ]; then
        echo "   ✅ systemd WorkingDirectory matches: $BASE_DIR"
    else
        echo "   ❌ systemd WorkingDirectory mismatch"
        echo "      installed: ${UNIT_DIR:-<unknown>}"
        echo "      current:   $BASE_DIR"
        echo "      → ./run/install_systemd.sh 실행 후 ./run/restart.sh"
        DEPLOY_OK=false
    fi

    if [ -n "$UNIT_ENV" ] && [ "$UNIT_ENV" = "$BASE_DIR/.env" ]; then
        echo "   ✅ systemd EnvironmentFile matches"
    elif [ -n "$UNIT_ENV" ]; then
        echo "   ❌ systemd EnvironmentFile mismatch: $UNIT_ENV"
        DEPLOY_OK=false
    fi

    if [ -n "$UNIT_EXEC" ] && [ "$UNIT_EXEC" = "$BASE_DIR/run/run.sh" ]; then
        echo "   ✅ systemd ExecStart matches"
    elif [ -n "$UNIT_EXEC" ]; then
        echo "   ❌ systemd ExecStart mismatch: $UNIT_EXEC"
        DEPLOY_OK=false
    fi
else
    echo "   ⚠️  systemd unit not found (local dev?)"
fi

if [ "$DEPLOY_OK" = false ]; then
    echo ""
    echo "   ⚠️  배포 설정 문제로 서비스가 시작되지 않을 수 있습니다."
fi
echo ""

# Check if timer is active
echo "📅 Timer Status:"
if systemctl is-active --quiet "${SERVICE_NAME}.timer"; then
    echo "   ✅ Timer is ACTIVE"
    systemctl list-timers "${SERVICE_NAME}.timer" --no-pager 2>/dev/null | tail -2 || true
else
    echo "   ❌ Timer is INACTIVE"
fi
echo ""

# Check last service run
echo "🔄 Last Service Run:"
systemctl status "${SERVICE_NAME}.service" --no-pager -l 2>/dev/null | head -15 || echo "   Service not found"
echo ""

# Check recent logs
echo "📋 Recent Logs (last 10 lines):"
journalctl -u "${SERVICE_NAME}.service" --no-pager -n 10 2>/dev/null || echo "   No logs found"
echo ""

# Check log files
echo "📁 Log Files:"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
if [ -d "$LOG_DIR" ]; then
    LATEST_LOG=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        echo "   Latest: $(basename "$LATEST_LOG")"
        echo "   Size: $(du -h "$LATEST_LOG" | cut -f1)"
        echo "   Last modified: $(stat -c %y "$LATEST_LOG" 2>/dev/null | cut -d. -f1)"
    else
        echo "   No log files found"
    fi
else
    echo "   Log directory not found: $LOG_DIR"
fi
echo ""

# Check state file
echo "💾 State File:"
STATE_FILE="${STATE_FILE:-$BASE_DIR/state.json}"
if [ -f "$STATE_FILE" ]; then
    echo "   ✅ State file exists: $STATE_FILE"
    echo "   Last modified: $(stat -c %y "$STATE_FILE" 2>/dev/null | cut -d. -f1)"
    if command -v jq &> /dev/null; then
        echo "   Current issue status:"
        jq -r '._global.has_issue // "unknown"' "$STATE_FILE" 2>/dev/null || echo "   (cannot parse)"
    fi
else
    echo "   ❌ State file not found: $STATE_FILE"
fi
