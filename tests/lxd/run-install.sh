#!/bin/bash
# Push the local SolStream repo into the test VM and run the install.

set -euo pipefail
VM=solstream-test
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { echo -e "\033[1;33m[run-install]\033[0m $*"; }

if ! lxc list "$VM" --format csv -c n 2>/dev/null | grep -q "^${VM}$"; then
  log "VM ${VM} doesn't exist. Run ./launch.sh first."
  exit 1
fi

# ─── 1. Tar the repo (skip .git/.venv/etc., keeps payload small) ─────────
log "Tarring repo from ${REPO_ROOT}…"
TAR=$(mktemp -t solstream-XXXXXX.tar)
tar -cf "$TAR" -C "$REPO_ROOT" \
  --exclude='.git' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='.venv' \
  --exclude='node_modules' \
  --exclude='build' \
  --exclude='dist' \
  .

log "Pushing into VM…"
lxc file push "$TAR" "${VM}/tmp/solstream.tar"
lxc exec "$VM" -- bash -c '
  rm -rf /opt/solstream
  mkdir -p /opt/solstream
  tar -xf /tmp/solstream.tar -C /opt/solstream
'
rm -f "$TAR"

# ─── 2. Install ansible + python-docker if not present ───────────────────
log "Installing ansible-core + docker python lib + base deps…"
lxc exec "$VM" -- bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq python3-venv git ansible-core mokutil \
    python3-docker python3-requests docker.io
  systemctl enable --now docker
  ansible-galaxy collection install community.docker community.general
' 2>&1 | tail -5

# ─── 3. Create streaming user + inventory ────────────────────────────────
log "Creating streamer user + inventory…"
lxc exec "$VM" -- bash -c '
  id streamer >/dev/null 2>&1 || useradd -m -s /bin/bash streamer
  passwd -d streamer
  loginctl enable-linger streamer
  cat > /opt/solstream/ansible/inventory/hosts.yml <<INV
all:
  children:
    solstream_hosts:
      hosts:
        localhost:
          ansible_connection: local
          ansible_user: root
          solstream_user: streamer
          solstream_skip_preflight: true
          solstream_enable_wireguard: false
INV
'

# ─── 4. Run the playbook ─────────────────────────────────────────────────
SKIP_TAGS="${SOLSTREAM_SKIP_TAGS:-}"
if [ -n "$SKIP_TAGS" ]; then
  log "Running playbook (skipping tags: $SKIP_TAGS)…"
  lxc exec "$VM" -- bash -c "
    cd /opt/solstream/ansible
    ansible-playbook -i inventory/hosts.yml solstream.yml --skip-tags $SKIP_TAGS
  "
else
  log "Running FULL playbook (will take ~15-20 min for gamescope build)…"
  lxc exec "$VM" -- bash -c '
    cd /opt/solstream/ansible
    ansible-playbook -i inventory/hosts.yml solstream.yml
  '
fi
