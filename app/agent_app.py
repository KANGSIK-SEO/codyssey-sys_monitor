#!/usr/bin/env python3
"""Reference agent app for monitor.sh validation.

본 과제에서 제공되는 Python 앱이 별도로 있다면 그쪽을 우선 사용한다.
이 파일은 부트 시퀀스(5단계), 0.0.0.0:15034 LISTEN, 일반 계정 실행을
재현·검증하기 위한 표준 참조 구현이다.
"""

from __future__ import annotations

import getpass
import os
import socket
import sys
from pathlib import Path

REQUIRED_ENV = [
    "AGENT_HOME",
    "AGENT_PORT",
    "AGENT_UPLOAD_DIR",
    "AGENT_KEY_PATH",
    "AGENT_LOG_DIR",
]


def step(idx: int, total: int, label: str, ok: bool, detail: str = "") -> None:
    status = "[OK]" if ok else "[FAIL]"
    suffix = f"  {detail}" if detail else ""
    print(f"[{idx}/{total}] {label:<38} {status}{suffix}")
    if not ok:
        sys.exit(1)


def main() -> None:
    total = 5

    # [1/5] User Account: root 금지, agent-* 계정에서 실행
    user = getpass.getuser()
    step(1, total, "Checking User Account", user != "root" and user.startswith("agent-"),
         f"(user={user})")

    # [2/5] Environment Variables
    missing = [k for k in REQUIRED_ENV if not os.environ.get(k)]
    step(2, total, "Verifying Environment Variables", not missing,
         "" if not missing else f"missing: {missing}")

    # [3/5] Required Files: t_secret.key
    key_path = Path(os.environ["AGENT_KEY_PATH"])
    step(3, total, "Checking Required Files", key_path.is_file(),
         f"(key={key_path})")

    # [4/5] Port Availability: bind 가능 여부
    port = int(os.environ["AGENT_PORT"])
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", port))
    except OSError as exc:
        step(4, total, "Checking Port Availability", False, f"({exc})")
    step(4, total, "Checking Port Availability", True, f"(0.0.0.0:{port})")

    # [5/5] Log Permission
    log_dir = Path(os.environ["AGENT_LOG_DIR"])
    can_log = log_dir.is_dir() and os.access(log_dir, os.W_OK)
    step(5, total, "Verifying Log Permission", can_log, f"({log_dir})")

    print("Agent READY")

    sock.listen(64)
    print(f"Listening on 0.0.0.0:{port}")
    try:
        while True:
            conn, addr = sock.accept()
            conn.sendall(b"AGENT_OK\n")
            conn.close()
    except KeyboardInterrupt:
        print("Shutting down.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
