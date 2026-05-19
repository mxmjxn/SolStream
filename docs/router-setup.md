# Router setup for remote streaming

For **LAN-only** use you can ignore this entire doc — SolStream works out of the box once installed.

For **remote streaming over the open internet** via WireGuard, your router/network is the only piece SolStream cannot configure for you. This page walks through the three things you must do yourself, plus common traps.

## TL;DR

1. Forward **UDP 51820** on your edge router to the SolStream host
2. Make sure **only one router is doing NAT** on that port (no double-NAT trap)
3. Disable any ISP-side "advanced security" / threat-blocking feature that might silently TLS-reject WireGuard or DDNS

That's it. Steps 1 and 2 are mandatory; step 3 has bitten enough users that it's worth checking even if you think it doesn't apply.

---

## Step 1 — Port forward

Where in your router admin:

- **Netgear Nighthawk** — Advanced Setup → Port Forwarding → Add Custom Service
- **TP-Link Archer** — Advanced → NAT Forwarding → Virtual Servers
- **Asus** — WAN → Virtual Server / Port Forwarding
- **Linksys** — Security → Apps and Gaming → Single Port Forwarding
- **Ubiquiti UniFi** — Network → Settings → Routing → Port Forwarding
- **OPNsense / pfSense** — Firewall → NAT → Port Forward
- **Quantum Fiber (Calix) gateway** — Advanced Setup → Security → Port Forwarding
- **Xfinity gateway (gateway mode)** — Advanced Settings → Port Forwarding

Rule:

| Field | Value |
|---|---|
| Protocol | **UDP** (not TCP, not "Both" if you can avoid it) |
| External port | `51820` |
| Internal IP | `<your SolStream host's LAN IP>` (e.g., 192.168.1.20) |
| Internal port | `51820` |
| Description | "WireGuard" or "SolStream" |

**Critical:** must be **UDP**. WireGuard is a UDP-only protocol. A TCP forward on the same port number won't help and won't error — peers just silently fail to handshake.

While you're in the router, also add a **DHCP reservation** for the SolStream host's MAC address pointing at its current IP. If the IP ever rotates, the port forward breaks silently.

---

## Step 2 — The double-NAT trap

If you have two routers in series (ISP modem-router + your own router), you have **two NAT layers**. Inbound UDP 51820 hits the *outer* (ISP) router first. If that router doesn't know to forward to the inner router, it drops the packet — your inner router's port-forward rule never sees anything.

### How to detect it

On your own router's admin, find the **WAN IP** ("Internet IP Address" on the Connection Status page). If it's:

- A **public IP** (e.g., `174.x.x.x`, `73.x.x.x`, anything outside RFC1918) → single NAT, you're fine
- A **private IP** (`10.x.x.x`, `192.168.x.x`, `172.16.x.x` – `172.31.x.x`) → **double NAT**
- A **CGNAT IP** (`100.64.x.x` – `100.127.x.x`) → ISP carrier-grade NAT — you cannot do inbound port forwarding at all; need IPv6 or a tunnel relay

### Fixing double NAT

**Best**: put the ISP gateway in **bridge / pass-through mode** so it acts as just a modem. Then your own router gets the real public IP. Everything just works after that. Downside: kills the ISP gateway's Wi-Fi.

**Next best**: keep both routers routing, but configure a **cascading port forward** — the ISP gateway forwards 51820/UDP to your inner router's WAN IP; your inner router then forwards 51820/UDP to the SolStream host. Two rules, two places, but no Wi-Fi loss.

**Worst (don't)**: DMZ the inner router to the ISP gateway. Functionally works but exposes everything behind the inner router.

For a cascading setup, also pin the inner router's WAN IP via DHCP reservation on the ISP gateway — same logic as the host-side reservation.

---

## Step 3 — ISP-side filtering ("security" features)

Some ISPs run transparent threat-intelligence filters on residential connections. These default-on filters:

- Block traffic to/from "known bad" domains
- Often false-positive on legitimate self-hosted services (DuckDNS, dynamic DNS in general, some VPN endpoints, GitHub Codespaces)
- Use TLS interception — they reject HTTPS handshakes to flagged destinations with `access denied` alerts

The most common offenders:

| ISP | Feature name | Where to disable |
|---|---|---|
| Comcast / Xfinity | **xFi Advanced Security** | Xfinity app → My Services → xFi Advanced Security → off. Or `xfinity.com/myxfi`. Or call support. |
| Quantum Fiber | "Connected Home" / **Cyber Security** | Gateway admin → Security → Cyber Security → off |
| Spectrum | **Security Shield** | My Spectrum app → Internet → Security |
| AT&T Fiber | (rare; gateway-dependent) | Gateway admin → Firewall → toggle off |

### How to know if you've been bitten

```bash
# From the SolStream host
curl -sS http://www.duckdns.org/update?domains=YOUR_DOMAIN\&token=YOUR_TOKEN\&ip=
```

If the response is HTML with `block.cloud.lionic.com` or similar block-page reference, you have a filter in the path. HTTPS to the same endpoint will return TLS error 0A000419 (access denied at the TLS layer).

### Why disabling this is safe enough

The filters are calibrated for grandma's web browsing — they catch known-bad domains (which lag the actual threats by days/weeks) and miss everything that matters (zero-days, phishing via legitimate sites, supply-chain attacks, IoT compromise). On a homelab box already running Pi-hole + NAT firewall + only WireGuard exposed to the internet, the ISP filter is providing no additional defense while breaking legitimate self-hosted services.

If you're nervous, the alternative is **Tailscale** — same WireGuard underneath but uses Tailscale's hole-punching + relay infrastructure, so you don't need *any* port forward and the ISP filter has nothing to block. Free for personal use. SolStream's `wireguard` role has an opt-in to use Tailscale instead of wg-easy.

---

## Verifying it all works

After all three steps:

```bash
# On the SolStream host
docker exec wg-easy wg show wg0 latest-handshakes
# epoch values for connected peers, 0 for never-connected
```

Toggle a peer's WireGuard tunnel on (from cellular or any non-LAN connection — Wi-Fi connected to the same network can give false negatives on routers without hairpin NAT). The peer's row should flip from `0` to a recent timestamp within 30 seconds.

If it stays `0`, work backwards:

1. From the peer device, try to send a UDP packet to your public IP:51820. `nc -u public.ip.address 51820` from a Linux client, or use a network tester app on phones.
2. On the SolStream host, watch incoming packets: `sudo tcpdump -i any udp port 51820`. If you see incoming packets but no handshake completes, the WG key config is wrong. If you don't see incoming packets, the port forward isn't routing properly.

---

## Optional: dynamic DNS

If your ISP doesn't give you a static public IP (most don't), use a DDNS service so peers can connect via a hostname that auto-updates. Options that work well with `wg-easy`:

| Provider | Free tier | Notes |
|---|---|---|
| DuckDNS | Yes, unlimited | Simplest; small Docker container handles updates |
| Cloudflare | Yes if you own a domain | Most robust; full API access |
| Hurricane Electric | Yes | Best technical control; IPv6-friendly |
| Dynu | Yes, limited | Alternative if DuckDNS is filtered |
| No-IP | Yes, requires monthly confirmation | Avoid unless you want the confirmation hassle |

SolStream installs a DuckDNS container by default; the `wireguard` role variables let you swap providers.
