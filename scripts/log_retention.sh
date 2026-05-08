#!/usr/bin/env bash
# 보너스 2: 시간 기반 로그 보존 정책
# - 7일 경과 *.log → gzip
# - 압축본 → /var/log/monitor/agent-app/archive/
# - 30일 경과 archive → 삭제
set -euo pipefail

LOG_DIR="/var/log/agent-app"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"
mkdir -p "$ARCHIVE_DIR"

# 안전장치: 디렉토리 미존재 / 쓰기 권한 없음 → 경고 후 종료
[ ! -d "$LOG_DIR" ] && { echo "[WARN] $LOG_DIR 미존재. 종료."; exit 0; }
[ ! -w "$ARCHIVE_DIR" ] && { echo "[WARN] $ARCHIVE_DIR 쓰기 권한 없음. 종료."; exit 0; }

# 7일 경과 .log → gzip
COMPRESSED=0
while IFS= read -r f; do
  gzip -f "$f"
  mv "${f}.gz" "$ARCHIVE_DIR/$(basename "$f").$(date +%Y%m%d).gz"
  COMPRESSED=$((COMPRESSED+1))
done < <(find "$LOG_DIR" -type f -name "*.log" -mtime +7 2>/dev/null || true)
echo "[INFO] 압축 이동: ${COMPRESSED}개"

# 30일 경과 .gz → 삭제
DELETED=0
while IFS= read -r f; do
  rm -f "$f"
  DELETED=$((DELETED+1))
done < <(find "$ARCHIVE_DIR" -type f -name "*.gz" -mtime +30 2>/dev/null || true)
echo "[INFO] 삭제: ${DELETED}개"
