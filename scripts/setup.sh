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

# secret.key 생성
echo agent_api_key_test | sudo tee "$AGENT_HOME/api_keys/secret.key" > /dev/null
sudo chown agent-admin:agent-core "$AGENT_HOME/api_keys/secret.key"
sudo chmod 640 "$AGENT_HOME/api_keys/secret.key"

# ============ monitor.sh 배치 ============
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
sudo cp "$SCRIPT_DIR/monitor.sh" "$AGENT_HOME/bin/monitor.sh"
sudo chown agent-dev:agent-core "$AGENT_HOME/bin/monitor.sh"
sudo chmod 750 "$AGENT_HOME/bin/monitor.sh"

# ============ cron 등록 (agent-admin) ============
CRON_LINE="* * * * * $AGENT_HOME/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1"
(sudo crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh"; echo "$CRON_LINE") | sudo crontab -u agent-admin -

echo ""
echo "=== 셋업 완료 ==="
echo "agent-admin 그룹: $(id agent-admin)"
echo "agent-dev   그룹: $(id agent-dev)"
echo "agent-test  그룹: $(id agent-test)"
sudo crontab -u agent-admin -l
echo ""
echo "=== 다음 단계 ==="
echo "1) 환경변수 설정 후 앱 실행: cd $AGENT_HOME && python3 agent-leak-app"
echo "2) 1~2분 후 로그 확인: tail /var/log/agent-app/monitor.log"
