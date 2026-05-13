#!/usr/bin/env bash
# 1회 실행: SSH 포트 변경, UFW 활성화, 계정/그룹/디렉토리 생성, monitor.sh 배치
# Ubuntu 22.04 기준. sudo 필요.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "[안내] root 직접 실행 비권장. sudo로 일반 사용자에서 실행하세요."
fi

# ============ SSH 포트 20022, root 차단 ============
SSHD=/etc/ssh/sshd_config
sudo sed -i.bak 's/^#\?Port .*/Port 20022/' "$SSHD"
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD"
grep -E '^(Port|PermitRootLogin)' "$SSHD"
sudo systemctl restart ssh

# ============ UFW 활성화 + 20022, 15034만 ============
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 20022/tcp comment 'SSH (alt port)'
sudo ufw allow 15034/tcp comment 'Agent app'
sudo ufw --force enable
sudo ufw status verbose

# ============ 계정/그룹 ============
for u in agent-admin agent-dev agent-test; do
  id "$u" >/dev/null 2>&1 || sudo useradd -m -s /bin/bash "$u"
done
sudo groupadd -f agent-common
sudo groupadd -f agent-core
sudo usermod -aG agent-common agent-admin
sudo usermod -aG agent-common agent-dev
sudo usermod -aG agent-common agent-test
sudo usermod -aG agent-core agent-admin
sudo usermod -aG agent-core agent-dev

# ============ 디렉토리 ============
AGENT_HOME=/home/agent-admin/agent-app
sudo -u agent-admin mkdir -p "$AGENT_HOME"/{upload_files,api_keys,bin}
sudo mkdir -p /var/log/agent-app
sudo chown agent-admin:agent-core /var/log/agent-app
sudo chmod 770 /var/log/agent-app

# upload_files: agent-common 모두 R/W
sudo chgrp agent-common "$AGENT_HOME/upload_files"
sudo chmod 770 "$AGENT_HOME/upload_files"

# api_keys: agent-core ONLY
sudo chgrp agent-core "$AGENT_HOME/api_keys"
sudo chmod 770 "$AGENT_HOME/api_keys"

# t_secret.key 생성 (요구사항 명시 파일명)
echo agent_api_key_test | sudo tee "$AGENT_HOME/api_keys/t_secret.key" > /dev/null
sudo chown agent-admin:agent-core "$AGENT_HOME/api_keys/t_secret.key"
sudo chmod 640 "$AGENT_HOME/api_keys/t_secret.key"

# ============ monitor.sh 배치 ============
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
sudo cp "$SCRIPT_DIR/monitor.sh" "$AGENT_HOME/bin/monitor.sh"
sudo chown agent-dev:agent-core "$AGENT_HOME/bin/monitor.sh"
sudo chmod 750 "$AGENT_HOME/bin/monitor.sh"

# ============ 환경변수 영속화 (/etc/profile.d) ============
ENV_FILE=/etc/profile.d/agent-app.sh
sudo tee "$ENV_FILE" > /dev/null <<EOF
export AGENT_HOME=$AGENT_HOME
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=\$AGENT_HOME/upload_files
export AGENT_KEY_PATH=\$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF
sudo chmod 644 "$ENV_FILE"

# ============ cron 등록 (agent-admin) ============
# cron은 비대화 셸이라 /etc/profile.d 미적용. 매 라인에 env를 명시한다.
CRON_ENV="AGENT_HOME=$AGENT_HOME AGENT_PORT=15034 AGENT_LOG_DIR=/var/log/agent-app AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files"
CRON_LINE="* * * * * $CRON_ENV $AGENT_HOME/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1"
(sudo crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh"; echo "$CRON_LINE") | sudo crontab -u agent-admin -

echo ""
echo "=== 셋업 완료 ==="
echo "agent-admin 그룹: $(id agent-admin)"
echo "agent-dev   그룹: $(id agent-dev)"
echo "agent-test  그룹: $(id agent-test)"
sudo crontab -u agent-admin -l
echo ""
echo "=== 다음 단계 ==="
echo "1) 새 셸에서 환경변수 자동 로드 (또는 source /etc/profile.d/agent-app.sh)"
echo "2) 일반 계정에서 앱 실행: sudo -u agent-admin -E bash -c 'cd \$AGENT_HOME && python3 agent_app.py'"
echo "3) 1~2분 후 로그 확인: sudo tail /var/log/agent-app/monitor.log"
