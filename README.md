# 시스템 관제 자동화 스크립트

Ubuntu 22.04 + 제공 Python 앱 환경에서 동작.

## 산출물

```
sys_monitor/
├── scripts/
│   ├── setup.sh             # 1회 실행: SSH/UFW/계정/디렉토리/cron 일괄 셋업
│   ├── monitor.sh           # 매분 cron 실행 (배치 위치: $AGENT_HOME/bin/)
│   ├── report.sh            # 보너스: monitor.log 통계 분석
│   └── log_retention.sh     # 보너스: 7일 압축 + 30일 삭제
└── docs/
    └── 요구사항_수행내역서.md
```

## 빠른 실행

```bash
# 1) 셋업 (SSH 포트, UFW, 계정, 디렉토리, cron 한 번에)
sudo bash scripts/setup.sh

# 2) 환경변수 + 앱 실행
source <(grep -E '^export' docs/요구사항_수행내역서.md | head -8)
sudo -u agent-admin bash -c "cd $AGENT_HOME && python3 agent_app.py"

# 3) 1~2분 후 자동 누적 확인
sudo tail /var/log/agent-app/monitor.log

# 4) 통계 보너스
sudo bash scripts/report.sh

# 5) 로그 보존 정책 (cron 등록 권장)
sudo bash scripts/log_retention.sh
```

## 핵심 정책

### 보안
- SSH 포트 20022 + Root 원격 차단
- UFW 인바운드: 20022, 15034 만 허용. 0-65535 전체 개방 X.
- IAM 등 분리: agent-admin / agent-dev / agent-test
- agent-common (모두): upload_files R/W
- agent-core (admin+dev only): api_keys, /var/log/agent-app

### monitor.sh 요구사항 매핑

| 요구사항 | 구현 |
|---|---|
| 프로세스/포트 헬스체크 | `pgrep -f` + `ss -tln` 후 비정상 시 exit 1 |
| 방화벽 점검 | `ufw status`, 비활성 시 [WARNING] |
| 리소스 수집 | `ps -p PID -o %cpu,%mem` + `df /` |
| 임계값 경고 | CPU>20, MEM>10, DISK>80 → [WARNING] |
| 로그 누적 | `/var/log/agent-app/monitor.log` |
| 로그 회전 | 10MB/10개 (스크립트 내 단순 로직) |
| 권한 | 750, agent-dev:agent-core |

### cron
- agent-admin이 매분 실행
- `* * * * * $AGENT_HOME/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1`
- agent-admin은 agent-core 그룹 소속 → 실행 권한 있음

## 보너스 1 — report.sh

`monitor.log` 분석. 평균/최대/최소 + 샘플 수 + 시작/종료 시간 옵션.

```bash
sudo bash scripts/report.sh                                    # 전체
sudo bash scripts/report.sh "2026-05-07 14:00" "2026-05-07 16:00"
```

## 보너스 2 — log_retention.sh

- `/var/log/agent-app/*.log` 중 7일 경과 → gzip
- `/var/log/monitor/agent-app/archive/*.gz` 중 30일 경과 → 삭제
- 디렉토리 미존재 / 권한 부족 등 안전한 종료 처리

cron 추가:
```
0 3 * * * /path/to/log_retention.sh
```
