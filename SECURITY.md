# Security policy

## Threat model

SolStream installs a remotely-accessible game-streaming host. The relevant attack surfaces:

- **Sunshine** (47984/47989/47990 TCP, 47998-48010 UDP) — has TLS + per-client pairing, but exposes a Vulkan/NVENC pipeline that could be a target
- **WireGuard** (51820/UDP) — has strong crypto + pre-shared keys + per-peer public keys. Low risk.
- **wg-easy web UI** (51821/TCP) — bcrypt-gated admin panel; should never be internet-exposed
- **The `install.sh` one-command bootstrap** — runs as root, modifies system files
- **The Ansible playbook** — runs as root, modifies system files
- **The web installer** — listens on 0.0.0.0:8080 during install; *temporary*, single-user

## Reporting a vulnerability

Email **maxim.jackson@live.com** with subject line `SECURITY: SolStream` and:

- A description of the vulnerability
- Steps to reproduce
- Affected component (CLI, webui, Ansible role, etc.)
- Suggested fix if you have one

**Please do not open a public issue** until we've coordinated a fix and disclosure timeline.

### Response expectations

This is a single-maintainer project. Realistic timeline:

- Acknowledgement: within 7 days
- Initial assessment: within 14 days
- Fix for critical issues: as soon as practical (no SLA)

## Known limitations / non-fixes

- **The Sunshine web UI uses a self-signed cert by default.** This is upstream behavior. Users see a browser warning on first visit and proceed past it. Replace `~/.config/sunshine/credentials/cert.pem` with a real cert if you want to fix this.
- **The wg-easy admin password is set via bcrypt hash at install time.** If the user picks a weak password, the install will accept it. The webui prompts but doesn't enforce strength.
- **The `install.sh` script runs `curl | sudo bash`** — the security of that depends entirely on the user trusting the URL they piped. We do not sign the install script (yet). v0.2 plan: ship signed releases + `install.sh` that verifies against a public key.
- **PSK rotation** for WireGuard peers isn't automated. Use the wg-easy admin UI to rotate.

## Things we've done that are security-relevant

- Sunshine binds to *all* interfaces by default, but the only thing internet-facing is WireGuard (51820/UDP). Sunshine itself only sees connections from WG peers or LAN.
- The webui is intended to be a *temporary* install-time service. After install completes, you should `Ctrl-C` it. Future: auto-shutdown the webui after the install reaches "done."
- The session wrapper runs as a regular user, not root. seatd brokers DRM access; no further privilege is needed.
- DKMS-built NVIDIA kernel modules are rejected by default under Secure Boot. The `nvidia-driver` role specifically opts for Canonical-signed precompiled modules when SB is enabled, preserving the security boundary.
