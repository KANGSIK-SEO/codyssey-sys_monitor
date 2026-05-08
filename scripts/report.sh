#!/usr/bin/env bash
# 보너스: monitor.log 분석. POSIX awk 호환 (BSD/GNU 모두 동작).
set -euo pipefail

LOG="/var/log/agent-app/monitor.log"
START="${1:-}"
END="${2:-}"
[ ! -f "$LOG" ] && { echo "[오류] 로그 파일이 없습니다: $LOG"; exit 2; }

awk -v s="$START" -v e="$END" '
function extract(line, label,    pat, m) {
  pat = label ":[0-9.]+%"
  if (match(line, pat)) {
    m = substr(line, RSTART, RLENGTH)
    sub(label ":", "", m); sub("%", "", m)
    return m + 0
  }
  return -1
}
function getts(line) {
  if (match(line, /\[[0-9-]+ [0-9:]+\]/)) {
    return substr(line, RSTART+1, RLENGTH-2)
  }
  return ""
}
{
  t = getts($0); if (t == "") next
  if (s != "" && t < s) next
  if (e != "" && t > e) next
  cpu = extract($0, "CPU"); if (cpu < 0) next
  mem = extract($0, "MEM")
  disk = extract($0, "DISK_USED")
  cpu_sum += cpu; mem_sum += mem; disk_sum += disk; n++
  if (n == 1 || cpu > cpu_max) { cpu_max = cpu; cpu_max_t = t }
  if (n == 1 || cpu < cpu_min) { cpu_min = cpu; cpu_min_t = t }
  if (n == 1 || mem > mem_max) { mem_max = mem; mem_max_t = t }
  if (n == 1 || mem < mem_min) { mem_min = mem; mem_min_t = t }
  if (n == 1 || disk > disk_max) disk_max = disk
  if (n == 1 || disk < disk_min) disk_min = disk
}
END {
  if (n == 0) { print "[정보] 분석할 데이터가 없습니다."; exit }
  printf "====== STATISTICS REPORT (%d samples) ======\n", n
  printf "[CPU]\n"
  printf "  Average : %.1f%%\n", cpu_sum / n
  printf "  Maximum : %.1f%% at %s\n", cpu_max, cpu_max_t
  printf "  Minimum : %.1f%% at %s\n", cpu_min, cpu_min_t
  printf "[Memory]\n"
  printf "  Average : %.1f%%\n", mem_sum / n
  printf "  Maximum : %.1f%% at %s\n", mem_max, mem_max_t
  printf "  Minimum : %.1f%% at %s\n", mem_min, mem_min_t
  printf "[Disk]\n"
  printf "  Average : %.1f%%\n", disk_sum / n
  printf "  Range   : %.0f%% ~ %.0f%%\n", disk_min, disk_max
}
' "$LOG"
