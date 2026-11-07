#!/usr/bin/env bash
# install-forgejo.sh
# Installs Forgejo on Fedora as a rootless Podman Quadlet service under a
# dedicated 'forgejo' system user. Safe to re-run.
#
# Usage:  sudo ./install-forgejo.sh
#
# Edit the settings below before running.

set -euo pipefail

# ---------------------------------------------------------------- settings ---
FORGEJO_TAG="15-rootless"            # 15 = LTS (EOL Jul 2027). Use 17-rootless for latest stable.
SVC_USER="forgejo"
DATA_ROOT="/srv/forgejo"
HTTP_PORT=3000
SSH_PORT=2222
LAN_DOMAIN="forge.home.jwmlab.com"

# Set to true to make the Tailscale HTTPS name canonical (ROOT_URL becomes
# https://<forge>.<tailnet>.ts.net/ via 'tailscale serve'). false = LAN name.
USE_TAILSCALE_SERVE=false
# ------------------------------------------------------------------------------

IMAGE="codeberg.org/forgejo/forgejo:${FORGEJO_TAG}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo."

# --------------------------------------------------------------- packages ---
log "Checking packages"
command -v podman >/dev/null || dnf install -y podman
command -v curl   >/dev/null || dnf install -y curl

# ------------------------------------------------------------ service user ---
log "Ensuring system user '${SVC_USER}'"
if ! id "$SVC_USER" &>/dev/null; then
  useradd --system --create-home --shell /sbin/nologin "$SVC_USER"
fi
SVC_UID=$(id -u "$SVC_USER")
SVC_GID=$(id -g "$SVC_USER")
SVC_HOME=$(getent passwd "$SVC_USER" | cut -d: -f6)

# Rootless Podman needs subordinate UID/GID ranges. useradd --system does not
# allocate them, so add a 65536 range after the highest existing one.
next_free_start() {
  local file=$1
  awk -F: 'BEGIN{m=100000} {e=$2+$3; if (e>m) m=e} END{print m}' "$file" 2>/dev/null || echo 100000
}
for kind in uid gid; do
  file="/etc/sub${kind}"
  touch "$file"
  if ! grep -q "^${SVC_USER}:" "$file"; then
    start=$(next_free_start "$file")
    end=$((start + 65535))
    log "Adding sub${kind} range ${start}-${end} for ${SVC_USER}"
    usermod "--add-sub${kind}s" "${start}-${end}" "$SVC_USER"
  fi
done

# ------------------------------------------------------- linger + user bus ---
log "Enabling linger so user services run without a login"
loginctl enable-linger "$SVC_USER"

RUNTIME_DIR="/run/user/${SVC_UID}"
for _ in $(seq 1 30); do
  [[ -S "${RUNTIME_DIR}/bus" ]] && break
  sleep 1
done
[[ -S "${RUNTIME_DIR}/bus" ]] || die "User manager for ${SVC_USER} did not start (${RUNTIME_DIR}/bus missing)."

# Run a command as the service user with a working user session environment.
as_svc() {
  (cd / && runuser -u "$SVC_USER" -- env \
      HOME="$SVC_HOME" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus" \
      "$@")
}

# Pick up the new subuid/subgid ranges if Podman was already initialized.
as_svc podman system migrate >/dev/null 2>&1 || true

# ------------------------------------------------------------- directories ---
log "Creating ${DATA_ROOT}/{data,config}"
install -d -o "$SVC_UID" -g "$SVC_GID" -m 0750 "$DATA_ROOT" "$DATA_ROOT/data" "$DATA_ROOT/config"

# ---------------------------------------------------------------- ROOT_URL ---
if [[ "$USE_TAILSCALE_SERVE" == true ]]; then
  command -v tailscale >/dev/null || die "USE_TAILSCALE_SERVE=true but tailscale is not installed."
  command -v python3   >/dev/null || dnf install -y python3
  TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
  [[ -n "$TS_NAME" ]] || die "Could not determine Tailscale DNS name."
  DOMAIN="$TS_NAME"
  ROOT_URL="https://${TS_NAME}/"
else
  DOMAIN="$LAN_DOMAIN"
  ROOT_URL="http://${LAN_DOMAIN}:${HTTP_PORT}/"
fi
log "ROOT_URL will be ${ROOT_URL}"

# ----------------------------------------------------------- quadlet unit ---
QUADLET_DIR="${SVC_HOME}/.config/containers/systemd"
QUADLET_FILE="${QUADLET_DIR}/forgejo.container"
log "Writing ${QUADLET_FILE}"
install -d -o "$SVC_UID" -g "$SVC_GID" -m 0755 \
  "${SVC_HOME}/.config" "${SVC_HOME}/.config/containers" "$QUADLET_DIR"

cat > "$QUADLET_FILE" <<EOF
# Managed by install-forgejo.sh
[Unit]
Description=Forgejo
Wants=network-online.target
After=network-online.target

[Container]
Image=${IMAGE}
ContainerName=forgejo
AutoUpdate=registry
# Map host user '${SVC_USER}' to the container's git user (1000)
UserNS=keep-id:uid=1000,gid=1000
Volume=${DATA_ROOT}/data:/var/lib/gitea:Z
Volume=${DATA_ROOT}/config:/etc/gitea:Z
Volume=/etc/localtime:/etc/localtime:ro
PublishPort=${HTTP_PORT}:3000
PublishPort=${SSH_PORT}:2222
Environment=FORGEJO__server__DOMAIN=${DOMAIN}
Environment=FORGEJO__server__ROOT_URL=${ROOT_URL}
Environment=FORGEJO__server__SSH_DOMAIN=${DOMAIN}
Environment=FORGEJO__server__SSH_PORT=${SSH_PORT}
Environment=FORGEJO__server__SSH_LISTEN_PORT=2222
Environment=FORGEJO__service__DISABLE_REGISTRATION=true

[Service]
Restart=always
# First start may include a slow image pull
TimeoutStartSec=600

[Install]
WantedBy=default.target
EOF
chown "$SVC_UID:$SVC_GID" "$QUADLET_FILE"
chmod 0644 "$QUADLET_FILE"

log "Validating Quadlet file"
if ! as_svc /usr/libexec/podman/quadlet -dryrun -user >/dev/null; then
  as_svc /usr/libexec/podman/quadlet -dryrun -user || true
  die "Quadlet rejected the unit file (see output above)."
fi

# ------------------------------------------------------------- image pull ---
log "Pulling ${IMAGE}"
as_svc podman pull "$IMAGE"

# ---------------------------------------------------------- start service ---
log "Starting forgejo.service (user ${SVC_USER})"
as_svc systemctl --user daemon-reload
as_svc systemctl --user restart forgejo.service
as_svc systemctl --user enable --now podman-auto-update.timer

# ---------------------------------------------------------------- firewall ---
if systemctl is-active --quiet firewalld; then
  log "Configuring firewalld"
  DEFAULT_ZONE=$(firewall-cmd --get-default-zone)
  zones=("$DEFAULT_ZONE")
  if ip link show tailscale0 &>/dev/null; then
    TS_ZONE=$(firewall-cmd --get-zone-of-interface=tailscale0 2>/dev/null || echo "$DEFAULT_ZONE")
    if [[ "$TS_ZONE" != "$DEFAULT_ZONE" && "$TS_ZONE" != "trusted" ]]; then
      zones+=("$TS_ZONE")
    fi
    echo "tailscale0 is in zone: ${TS_ZONE}"
  else
    warn "tailscale0 not found; only configuring default zone (${DEFAULT_ZONE})."
  fi
  for z in "${zones[@]}"; do
    echo "Opening ${HTTP_PORT}/tcp and ${SSH_PORT}/tcp in zone ${z}"
    firewall-cmd --permanent --zone="$z" --add-port="${HTTP_PORT}/tcp" --add-port="${SSH_PORT}/tcp" >/dev/null
  done
  firewall-cmd --reload >/dev/null
else
  warn "firewalld not active; skipping firewall configuration."
fi

# ---------------------------------------------------------- tailscale serve ---
if [[ "$USE_TAILSCALE_SERVE" == true ]]; then
  log "Configuring tailscale serve -> localhost:${HTTP_PORT}"
  tailscale serve --bg "$HTTP_PORT"
fi

# ------------------------------------------------------------ health check ---
log "Waiting for Forgejo to answer on localhost:${HTTP_PORT}"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://127.0.0.1:${HTTP_PORT}/"; then
    ok=1; break
  fi
  sleep 2
done

if [[ "${ok:-0}" == 1 ]]; then
  log "Forgejo is up"
  cat <<EOF

Next steps:
  1. Open ${ROOT_URL} in a browser.
  2. On the setup page choose SQLite, create the admin account at the bottom, click Install.
  3. Add your SSH key, then test:  ssh -p ${SSH_PORT} git@${DOMAIN}

Useful commands (run from your own account):
  sudo systemctl --user -M ${SVC_USER}@ status forgejo
  sudo journalctl _UID=${SVC_UID} -f
  sudo systemctl --user -M ${SVC_USER}@ restart forgejo
EOF
else
  warn "Forgejo did not respond within 2 minutes. Recent logs:"
  journalctl _UID="$SVC_UID" -n 50 --no-pager || true
  exit 1
fi
