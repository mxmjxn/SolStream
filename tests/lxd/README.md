# LXD VM test environment

Reproducible Ubuntu 24.04 VM for testing SolStream's install path without GPU hardware. The Vagrant-based environment in `tests/vagrant/` does roughly the same thing but Vagrant needs VirtualBox or libvirt + a working `vagrant-libvirt` plugin. LXD is a one-command install on Ubuntu and ships native VM support.

## What this tests

✅ apt dependency resolution for every role  
✅ Ansible variable plumbing + Jinja templating + handlers  
✅ Role idempotency on re-runs  
✅ Cross-role interactions (lingering before pipewire, etc.)  
✅ User-systemd reachability (the DBUS_SESSION_BUS_ADDRESS gotcha)  
✅ Source builds (wayland, gamescope, i686 WSI cross-build)  
✅ Steam multiarch + i386 NVIDIA stack installation  
✅ Sunshine .deb install  

## What this can't test

❌ NVIDIA driver actually loading (no GPU)  
❌ Synthetic EDID making DP-1 connected (no real DRM)  
❌ gamescope DRM backend  
❌ Sunshine NVENC encoding  
❌ End-to-end streaming  

## One-time host setup

```bash
# Install LXD
sudo snap install lxd
sudo usermod -aG lxd $USER
newgrp lxd   # or log out + back in
```

### LXD init pitfalls (we hit all of these)

The default `lxd init --auto` will fail on hosts with **Pi-hole or any process owning port 53**, because LXD's bridge runs `dnsmasq` which tries to bind port 53 host-wide. Use the preseed in [`setup.sh`](setup.sh) instead — it sets `raw.dnsmasq: port=0` to disable DNS-on-53.

Even with the preseed, hosts running **Docker** also need an iptables hole punched, because Docker sets `FORWARD` policy to `DROP` and only allows its own bridge:

```bash
sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -I DOCKER-USER -o lxdbr0 -j ACCEPT
```

The setup script does this automatically.

Finally — without dnsmasq's DNS server running, your VMs won't get a working `/etc/resolv.conf` via DHCP. The setup script pushes `1.1.1.1`/`8.8.8.8` as DHCP option 6, then also writes `/etc/resolv.conf` directly inside the VM as a belt-and-suspenders.

## Quick run

```bash
cd tests/lxd
./setup.sh                # one-time LXD init (idempotent)
./launch.sh               # spin up the test VM
./run-install.sh          # push repo + run the playbook
./teardown.sh             # destroy the VM (keep LXD config)
```

After `run-install.sh` finishes, you can:

- `lxc shell solstream-test` — interactive shell
- `lxc exec solstream-test -- ansible-playbook ...` — re-run with custom args
- `lxc file push <local> solstream-test/path/in/vm` — overwrite files in-VM for iterative debugging

## Skipping GPU-required roles

If you don't want to wait for `gamescope-build` (~10 min) or aren't testing the GPU path, skip the heavy roles:

```bash
lxc exec solstream-test -- bash -c '
  cd /opt/solstream/ansible
  ansible-playbook -i inventory/hosts.yml solstream.yml \
    --skip-tags gamescope,sunshine,wireguard,kernel
'
```

You still get a meaningful test of nvidia-driver (signed-modules path), steam, pipewire-session, session-wrapper, and discoverability.

## Known false-negatives on the VM

These are environmental issues that wouldn't happen on real hardware:

| Symptom | Why it happens | What it would do on real hardware |
|---|---|---|
| `gamescope-sunshine.service` enters `activating` then `failed` | No real GPU, no DRM device | Service actually streams |
| `wireplumber.service` failed to start | No real audio device | Wireplumber works once audio HW exists |
| `synthetic EDID injected but DP-1 still disconnected` | LXD VM has no NVIDIA DRM driver | EDID injection works after reboot |

The playbook's `doctor` role will report red on these in the VM. That's correct behavior — we want it red until real hardware is in place.
