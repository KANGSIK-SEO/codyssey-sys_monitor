#!/usr/bin/env bash
# /home/agent-admin/agent-app/bin/monitor.sh
# 권한: 750 (rwxr-x---), 소유 agent-dev:agent-core
# cron 매분 실행 (agent-admin)
set -euo pipefail

PROC="agent_app.py"
PORT=15034
LOG_FILE="/var/log/agent-app/monitor.log"
LOG_MAX_SIZE=$((10*1024*1024))   # 10MB
LOG_MAX_FILES=10

# 임계값
CPU_WARN=20
MEM_WARN=10
DISK_WARN=80

# ============ 로그 회전 (단순 구현) ============
rotate_log() {
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE")" -ge "$LOG_MAX_SIZE" ]; then
    for i in $(seq $((LOG_MAX_FILES - 1)) -1 1); do
      [ -f "${LOG_FILE}.$i" ] && mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    [ -f "${LOG_FILE}.${LOG_MAX_FILES}" ] && rm -f "${LOG_FILE}.$((LOG_MAX_FILES+1))"
  fi
}

# ============ HEALTH CHECK ============
echo "====== SYSTEM MONITOR RESULT ======"
echo ""
echo "[HEALTH CHECK]"

PID=$(pgrep -f "$PROC" | head -1 || true)
if [ -z "$PID" ]; then
  echo "Checking process '$PROC'... [FAIL]"
  exit 1
fi
echo "Checking process '$PROC'... [OK] (PID: $PID)"

if ! ss -tln | awk '{print $4}' | grep -qE ":${PORT}\$"; then
  echo "Checking port $PORT... [FAIL]"
  exit 1
fi
echo "Checking port $PORT... [OK]"

# ============ FIREWALL / PORT EXPOSURE CHECK (sudo 미사용) ============
# 직접 ufw status를 보려면 root 권한이 필요하므로, 일반 계정에서 가능한
# 포트 LISTEN 상태로 방화벽 정책 준수 여부를 간접 검증한다.
SSH_PORT=20022
if ! ss -tln | awk '{print $4}' | grep -qE ":${SSH_PORT}\$"; then
  echo "[WARNING] SSH 포트 ${SSH_PORT} 미개방 — 방화벽/SSH 설정 확인 필요"
fi
if ss -tln | awk '{print $4}' | grep -qE ":22\$"; then
  echo "[WARNING] 기본 SSH 포트 22가 노출됨 — 보안 정책 위반"
fi

# ============ RESOURCE ============
echo ""
echo "[RESOURCE MONITORING]"
CPU=$(ps -p "$PID" -o %cpu= | tr -d ' ')
MEM=$(ps -p "$PID" -o %mem= | tr -d ' ')
DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK_USED}%"

# ============ 임계값 경고 (경고만, 종료 X) ============
# awk로 부동소수 비교 (bash는 정수만 지원). 명시적 if 문이 가독성·안정성 ↑
if awk -v c="$CPU" -v t="$CPU_WARN" 'BEGIN{ exit !(c+0 > t) }'; then
  echo "[WARNING] CPU threshold exceeded (${CPU}% > ${CPU_WARN}%)"
fi
if awk -v m="$MEM" -v t="$MEM_WARN" 'BEGIN{ exit !(m+0 > t) }'; then
  echo "[WARNING] MEM threshold exceeded (${MEM}% > ${MEM_WARN}%)"
fi
if [ "${DISK_USED:-0}" -gt "$DISK_WARN" ]; then
  echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > ${DISK_WARN}%)"
fi

# ============ 로그 회전 + 기록 ============
rotate_log
TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "[${TS}] PID:${PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK_USED}%" >> "$LOG_FILE"
echo ""
echo "[INFO] Log appended: $LOG_FILE"
