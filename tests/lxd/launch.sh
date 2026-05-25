#!/bin/bash
# Spin up the SolStream test VM. Idempotent — won't re-launch if already there.

set -euo pipefail
VM=solstream-test

log() { echo -e "\033[1;33m[launch]\033[0m $*"; }

if lxc list "$VM" --format csv -c n 2>/dev/null | grep -q "^${VM}$"; then
  STATE=$(lxc list "$VM" --format csv -c s)
  log "VM ${VM} already exists (state: ${STATE})"
  if [ "$STATE" != "RUNNING" ]; then
    lxc start "$VM"
    log "started"
  fi
else
  log "Launching ${VM} (downloads image first time, ~1-3 min)…"
  lxc launch ubuntu:24.04 "$VM" --vm \
    -c limits.cpu=4 \
    -c limits.memory=4GiB \
    -d root,size=20GiB
fi

# Wait for IPv4
log "Waiting for IP…"
for i in $(seq 1 60); do
  IP=$(lxc list "$VM" -c 4 --format csv 2>/dev/null | grep -oE "10\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
  if [ -n "$IP" ]; then
    log "VM IP: $IP"
    break
  fi
  sleep 2
done

# Belt-and-suspenders DNS — set /etc/resolv.conf inside the VM
log "Setting VM /etc/resolv.conf (immutable so docker/systemd-resolved won't clobber it)…"
lxc exec "$VM" -- bash -c '
  chattr -i /etc/resolv.conf 2>/dev/null || true
  rm -f /etc/resolv.conf
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
  chattr +i /etc/resolv.conf 2>/dev/null || true
'

# Verify
if lxc exec "$VM" -- ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
  log "VM has internet ✓"
else
  log "VM CANNOT reach 1.1.1.1 — likely Docker iptables. Re-run setup.sh."
  exit 1
fi

log "Done. Next:  ./run-install.sh"
