#!/bin/bash
# One-time LXD setup for SolStream testing. Idempotent.
#
# Handles three host-environment landmines we hit during development:
#   1. Pi-hole / anything binding port 53 host-wide breaks LXD's dnsmasq
#   2. Docker's FORWARD chain blocks LXD bridge traffic
#   3. Without dnsmasq DNS, VMs don't get a working /etc/resolv.conf

set -euo pipefail

SUBNET="10.241.42.1/24"

log() { echo -e "\033[1;33m[setup]\033[0m $*"; }

# ─── 1. Verify LXD is installed ──────────────────────────────────────────
if ! command -v lxc >/dev/null; then
  log "LXD not installed. Run: sudo snap install lxd; sudo usermod -aG lxd \$USER"
  exit 1
fi

# ─── 2. Init LXD if not initialized ──────────────────────────────────────
if ! lxc storage list 2>/dev/null | grep -q default; then
  log "Initializing LXD with port-0 dnsmasq (dodges port-53 conflicts)…"
  PRESEED=$(mktemp)
  cat > "$PRESEED" <<PRESEED_END
config: {}
networks:
  - name: lxdbr0
    type: bridge
    config:
      ipv4.address: ${SUBNET}
      ipv4.nat: "true"
      ipv6.address: none
      raw.dnsmasq: |
        port=0
        dhcp-option=6,1.1.1.1,8.8.8.8
storage_pools:
  - name: default
    driver: dir
profiles:
  - name: default
    devices:
      eth0:
        name: eth0
        network: lxdbr0
        type: nic
      root:
        path: /
        pool: default
        type: disk
PRESEED_END
  sudo lxd init --preseed < "$PRESEED"
  rm -f "$PRESEED"
else
  log "LXD already initialized"
fi

# ─── 3. Punch through Docker FORWARD policy if Docker is installed ───────
if command -v docker >/dev/null && sudo iptables -L FORWARD -n 2>/dev/null | grep -q DOCKER-USER; then
  for direction in "-i lxdbr0" "-o lxdbr0"; do
    if ! sudo iptables -C DOCKER-USER $direction -j ACCEPT 2>/dev/null; then
      log "Adding iptables rule: DOCKER-USER $direction -j ACCEPT"
      sudo iptables -I DOCKER-USER $direction -j ACCEPT
    fi
  done
fi

log "Setup complete. Next:  ./launch.sh"
