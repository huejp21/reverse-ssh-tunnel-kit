#!/usr/bin/env bash
set -uo pipefail

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SELFDIR/revtun.conf"
KEY="$HOME/.ssh/id_rtun"
UNIT=revtun

ask_config() {
  [ -f "$CONF" ] && . "$CONF"
  [ -n "${RELAY_IP:-}" ]   || read -rp "Relay IP (the PC you connect FROM): " RELAY_IP
  [ -n "${RELAY_USER:-}" ] || read -rp "Relay login user: " RELAY_USER
  RELAY_PORT="${RELAY_PORT:-22}"
  FWD_PORT="${FWD_PORT:-2222}"
  EXPOSE_PORT="${EXPOSE_PORT:-22}"
  printf 'RELAY_IP=%s\nRELAY_USER=%s\nRELAY_PORT=%s\nFWD_PORT=%s\nEXPOSE_PORT=%s\n' \
    "$RELAY_IP" "$RELAY_USER" "$RELAY_PORT" "$FWD_PORT" "$EXPOSE_PORT" > "$CONF"
}

ensure_sshd() {
  systemctl is-active --quiet ssh 2>/dev/null && return
  echo "Enabling local SSH server (sudo)..."
  sudo systemctl enable --now ssh
}

ensure_key() {
  [ -f "$KEY" ] && return
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$KEY" -N '' -C "revtun-$(hostname)"
}

key_ok() {
  ssh -p "$RELAY_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    -i "$KEY" "${RELAY_USER}@${RELAY_IP}" exit 2>/dev/null
}

push_key() {
  echo "Registering key on relay ${RELAY_USER}@${RELAY_IP} (enter relay password once)..."
  local pub ps enc
  pub="$(cat "$KEY.pub")"
  ps="\$id=[Security.Principal.WindowsIdentity]::GetCurrent(); \$a=\$id.Groups.Value -contains 'S-1-5-32-544'; if(\$a){\$f=\"\$env:ProgramData\\ssh\\administrators_authorized_keys\"}else{\$d=\"\$env:USERPROFILE\\.ssh\"; New-Item -ItemType Directory -Force \$d|Out-Null; \$f=\"\$d\\authorized_keys\"}; if(-not(Select-String -Path \$f -SimpleMatch -Pattern '$pub' -Quiet -ErrorAction SilentlyContinue)){Add-Content \$f '$pub' -Encoding ascii}; if(\$a){icacls \$f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'|Out-Null}; 'KEY_REGISTERED'"
  enc="$(printf '%s' "$ps" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)"
  ssh -p "$RELAY_PORT" -o StrictHostKeyChecking=accept-new "${RELAY_USER}@${RELAY_IP}" \
    powershell -NoProfile -EncodedCommand "$enc"
}

start_tunnel() {
  if systemctl --user is-active --quiet "$UNIT"; then echo "tunnel already ON"; return; fi
  systemctl --user reset-failed "$UNIT" 2>/dev/null || true
  systemd-run --user --unit="$UNIT" --property=Restart=always --property=RestartSec=10 \
    /usr/bin/ssh -NT -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    -p "$RELAY_PORT" -i "$KEY" -R "127.0.0.1:${FWD_PORT}:127.0.0.1:${EXPOSE_PORT}" "${RELAY_USER}@${RELAY_IP}"
}

case "${1:-on}" in
  on)
    ask_config
    ensure_sshd
    ensure_key
    key_ok || push_key
    start_tunnel
    sleep 3
    systemctl --user --no-pager status "$UNIT" 2>&1 | head -5
    echo "Relay can now connect with:  ssh -p ${FWD_PORT} $(whoami)@127.0.0.1"
    ;;
  off)
    systemctl --user stop "$UNIT" 2>/dev/null || true
    systemctl --user reset-failed "$UNIT" 2>/dev/null || true
    systemctl --user stop worktunnel 2>/dev/null || true
    systemctl --user reset-failed worktunnel 2>/dev/null || true
    echo "tunnel off"
    ;;
  status)
    systemctl --user is-active --quiet "$UNIT" && echo "revtun ON" || { systemctl --user is-active --quiet worktunnel && echo "legacy worktunnel ON" || echo "tunnel OFF"; }
    ;;
  *) echo "usage: $0 {on|off|status}"; exit 1;;
esac
