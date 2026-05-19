# Vagrant test environment

Spins up a fresh Ubuntu 24.04 VM and provisions it with the SolStream CLI + playbook. This is how role changes get tested without touching real hardware.

## What it tests

✅ apt dependency resolution for every role  
✅ CLI subcommands work end-to-end  
✅ Role idempotency (running twice shouldn't break things)  
✅ Playbook syntax + variable plumbing  

## What it can't test

❌ Anything that needs a real NVIDIA GPU (driver install, KMS modeset, gamescope+sunshine actually rendering)  
❌ Anything that needs working DRM (gamescope `--backend drm` fails without `/dev/dri/card0`)  
❌ Streaming end-to-end  

For GPU-passthrough testing you'd want a libvirt host with VFIO and a spare GPU. That's planned for v0.2 in `tests/vagrant/Vagrantfile.gpu`.

## Quick start

```bash
cd tests/vagrant
vagrant up                          # ~3 minutes first time
vagrant ssh -c 'solstream version'  # smoke test
vagrant ssh                         # interactive shell
```

Inside the VM:

```bash
# Run the CLI tests
cd /vagrant/cli && PYTHONPATH=. python3 -m unittest discover tests/

# Dry-run the install (skip GPU-dependent roles since the VM has no GPU)
sudo solstream install --local --check --skip-tags nvidia,kernel,gamescope
```

## Teardown

```bash
vagrant destroy -f
```

## Requirements

- Vagrant 2.4+
- VirtualBox 7+ OR libvirt + vagrant-libvirt
- ~10 GB free disk
- ~4 GB free RAM
