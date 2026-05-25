#!/bin/bash
# Tear down the SolStream test VM (keep LXD config — re-launchable via launch.sh).

set -euo pipefail
VM=solstream-test

if lxc list "$VM" --format csv -c n 2>/dev/null | grep -q "^${VM}$"; then
  echo "Stopping + deleting VM ${VM}…"
  lxc stop "$VM" --force 2>/dev/null || true
  lxc delete "$VM" --force
fi
echo "Done. (LXD itself is left running; uninstall with: sudo snap remove lxd)"
