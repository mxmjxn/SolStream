# Troubleshooting

This page is the **encyclopedia of every failure mode** seen building real SolStream deployments. The Ansible roles pre-solve all of these; the docs here are for the cases where it didn't (a future kernel update, a different distro, custom hardware) and you need to debug.

Use `solstream doctor` first — it runs targeted checks for most of these. If `doctor` is green and you're still broken, the manual checks below are next.

---

## Driver / kernel / boot

### `nvidia-smi` says "couldn't communicate with the NVIDIA driver"

Almost always one of:

| Cause | Check | Fix |
|---|---|---|
| Secure Boot is on, modules unsigned | `mokutil --sb-state` + `dmesg \| grep "Key was rejected"` | Install signed precompiled: `linux-modules-nvidia-<gen>-open-<kernel>-generic` instead of DKMS |
| Kernel was upgraded, no matching `linux-modules-nvidia-*` for new kernel | `uname -r` vs `dpkg -l \| grep linux-modules-nvidia` | `apt install linux-modules-nvidia-<gen>-open-<new-kernel>-generic` |
| `nvidia.ko` exists but `/dev/nvidia*` device nodes don't | `lsmod \| grep nvidia` + `ls /dev/nvidia*` | `sudo nvidia-modprobe -c0 -u` to create nodes |
| GPU is in a bad power state | `nvidia-smi -q -d POWER` | `sudo nvidia-smi --persistence-mode=1` |

### Synthetic EDID didn't take after reboot

```bash
cat /sys/class/drm/card0-DP-1/status   # expect "connected"; if "disconnected" the EDID didn't load
```

Check, in order:

1. `cat /proc/cmdline` includes `drm.edid_firmware=DP-1:edid/headless-1440p120.bin video=DP-1:e`
2. `/lib/firmware/edid/headless-1440p120.bin` exists and is exactly 128 bytes
3. `dmesg | grep -i edid` — look for "Got built-in EDID base block" or "EDID firmware failed to load"
4. `edid-decode /lib/firmware/edid/headless-1440p120.bin` validates without errors

If the file is wrong size, regenerate with `python3 files/edid/make_edid.py`. If the kernel can't find the firmware, run `update-initramfs -u -k all`.

### Modules built with DKMS but Secure Boot rejects them

This is the classic Ubuntu + NVIDIA + Secure Boot footgun. You have three options:

1. **Switch to precompiled signed modules** (SolStream default): `apt install linux-modules-nvidia-<gen>-open-<kernel>-generic`, then `apt remove nvidia-dkms-*-open`. No reboot needed; the right modules are immediately loadable.
2. **Enroll a MOK** for your DKMS key: needs interactive boot-time prompt (a real screen). Not viable for headless servers without IPMI/KVM.
3. **Disable Secure Boot** in firmware: works but reduces security posture.

`#1` is what `solstream install` does.

---

## gamescope / display

### gamescope fails to acquire DRM master ("Could not open KMS device")

`seatd` isn't running or your user isn't in the `video` group.

```bash
systemctl status seatd
ls -la /run/seatd.sock      # expect: srwxrwx--- root video
groups                       # expect: video listed
```

Fix:
```bash
sudo apt install seatd
sudo systemctl enable --now seatd
sudo usermod -aG video $USER
# log out + back in (or restart your systemd-user instance) for group membership to apply
```

### Sunshine returns 503 "Failed to initialize video capture/encoding"

Sunshine's startup encoder probe couldn't find a display. Usually:

- `gamescope-sunshine.service` isn't running (or hasn't claimed DP-1 yet)
- `/sys/class/drm/card0-DP-1/status` is `disconnected` (EDID didn't load)
- gamescope started with `--backend headless` instead of `--backend drm` (won't expose a KMS connector for Sunshine to capture)

Check `journalctl --user -u gamescope-sunshine.service` for the gamescope startup logs. If gamescope says "Could not open KMS device", see the `seatd` section above.

### "Gamescope WSI Layer Error" popup at game launch

Several variants of this exist. In order of likelihood:

| Variant | Cause | Fix |
|---|---|---|
| Popup appears, game won't launch | i686 WSI layer not installed; Steam's 32-bit binary tries to load it and fails | `solstream install` builds + installs both x86_64 and i686 layers |
| Popup appears but game launches if you click OK | Another Vulkan layer (NV_optimus, etc.) is wrapping surface creation before gamescope's hook | Set `VK_LOADER_LAYERS_DISABLE=VK_LAYER_NV_optimus,VK_LAYER_NV_present,VK_LAYER_INTEL_nullhw` in the session env |
| Popup keeps appearing under Proton/DXVK titles | The Pressure Vessel sandbox can't see `/usr/local/lib/...`, WSI layer doesn't load inside the game | SolStream patches the dialog out (it's diagnostic-only — the fallback path works) |

The patch lives at `patches/gamescope-wsi-suppress-dialog.patch` and gets applied during `gamescope-build` role.

### Steam Big Picture menu feels laggy

That's *Steam Big Picture itself*, not the stream. The CEF-based GamepadUI runs with `--disable-gpu-compositing --disable-gpu` flags from Valve, so it's CPU-rendered. **Gameplay** uses Vulkan/OpenGL and is sharp.

If you want to validate this: stream a real game and compare in-game feel to in-menu feel. If in-game also feels off, capture metrics with `solstream metrics 60` and check encoder latency.

---

## Audio

### No sound on the stream, despite gameplay clearly making noise on the host

```bash
pactl list short sinks    # is Sunshine-Sink there?
pactl info | grep "Default Sink"   # is Sunshine-Sink the default?
```

If `Sunshine-Sink` is missing, `solstream-session.sh` either didn't run or `pulseaudio-utils` isn't installed (`pactl` not on PATH). Reinstall the `pipewire-session` role: `solstream install --only pipewire-session`.

If `Sunshine-Sink` exists but isn't default, the game is outputting to some other sink. Set the game's audio device in Steam → Settings → Audio.

### Sunshine logs `Couldn't set default-sink [auto_null]: No such entity`

Sunshine's config has `audio_sink = auto_null` (default), but no such sink exists. Set `audio_sink = Sunshine-Sink` in `~/.config/sunshine/sunshine.conf`.

---

## Steam-side gotchas

### Steam wrapper hangs forever on first launch

Ubuntu's `/usr/games/steam` shell wrapper shows a `zenity` prompt to confirm Steam install. On a headless box with no display server attached to the host, that dialog gets routed to gamescope's Xwayland — but if you haven't pressed "Install" via a Moonlight client first, the wrapper blocks indefinitely.

SolStream's `solstream-session.sh` drops a `zenity` stub on PATH that auto-returns 0 (success), so the prompt auto-accepts. If you're hitting this manually:

```bash
mkdir -p /tmp/zenity-stub
printf '#!/bin/sh\nexit 0\n' > /tmp/zenity-stub/zenity
chmod +x /tmp/zenity-stub/zenity
PATH=/tmp/zenity-stub:$PATH /usr/games/steam
```

### Steam Big Picture renders but the controller doesn't respond

Three places to check:

1. `ls /sys/class/input/event*/device/name | xargs -I{} sh -c 'echo {}: $(cat {})'` should show `Sunshine X-Box One (virtual) pad` while a client is connected.
2. `evtest /dev/input/eventN` (where N is the Sunshine virtual pad) while pressing buttons on the client — should print BTN_SOUTH etc. events.
3. If host-side events are flowing but Steam doesn't respond, check that Moonlight client's touch-input mode is set to **on-screen gamepad** (not "trackpad" or "native touch"). Or pair a real Bluetooth controller to the client device — far better experience anyway.

---

## Network / WireGuard / remote streaming

### WireGuard peer never handshakes

```bash
docker exec wg-easy wg show wg0 latest-handshakes
# "0" for a peer = never connected; non-zero epoch = connected at that time
```

Always 0 across all peers → packets aren't reaching `wg-easy`. Causes, in order of likelihood:

1. **Router port forward missing/wrong protocol.** WG is UDP — TCP forwards don't work. Verify in router admin.
2. **Double NAT.** If you have an ISP modem-router + your own router behind it, you need port-forwards on *both*. Check the inner router's WAN IP — if it's a private range (192.168.x.x, 10.x.x.x), you're double-NATed.
3. **ISP filter blocking inbound UDP 51820.** Rare, but Comcast Business plans and some mobile carriers do this. Test by sending a UDP packet from a phone on cellular to your public IP and check tcpdump on the wg-easy container.

### DDNS update failing with TLS errors

```
TLS connect error: error:0A000419:SSL routines::tlsv1 alert access denied
```

That's a TLS-layer rejection from upstream. On Comcast residential, this is almost always **xFi Advanced Security** (the Lionic-powered filter) classifying DuckDNS as "malicious." Disable it:

- Xfinity app → My Services → xFi Advanced Security → off
- Or call support and ask to disable it server-side
- Or switch to a different DDNS provider (CloudFlare, Hurricane Electric, dynu)

To confirm filter involvement, try plain HTTP to the same endpoint:
```bash
curl -s "http://www.duckdns.org/update?domains=...&token=...&ip="
# If response contains "lionic" or a "block page" HTML, the ISP filter is the cause
```

### Stream works on LAN but not over WireGuard

If WG handshakes succeed but Moonlight can't reach Sunshine through the tunnel:

```bash
# From a WG-connected client device
ping 192.168.1.20            # should succeed
curl -k https://192.168.1.20:47990   # should return 307
```

If ping fails: peer's `AllowedIPs` doesn't include your LAN range. Edit the peer in wg-easy: set `AllowedIPs` to `192.168.1.0/24, 10.8.0.0/24` (or `0.0.0.0/0` for full tunnel).

If ping works but Sunshine doesn't respond: the wg-easy container's NAT rules might not be forwarding to the host. Check `docker exec wg-easy iptables -t nat -S` — you want a `MASQUERADE` rule on `10.8.0.0/24`.

---

## Streaming quality

### High latency despite green network stats

In Moonlight's overlay, the relevant numbers are:

- **Host processing latency** — Sunshine's encode time. Should be < 5 ms avg on a 3070-class GPU. If higher, lower `nvenc_preset` (toward P4/P5), disable `nvenc_twopass`.
- **Network latency** — depends on physical hops. LAN should be < 2 ms; internet typically 20–80 ms.
- **Decode latency** — client-side. If high, lower the bitrate or resolution.

Run `solstream metrics 60` during a session to get a CSV of GPU/encoder utilization while you play.

### Stream is choppy / drops frames

Check `Frames dropped due to network jitter` in the Moonlight overlay first. If > 0%:

- Wired Ethernet wherever possible
- For Wi-Fi clients, prefer 5 GHz, channel 36–48 or 149–161
- Lower the bitrate (50 Mbps is plenty for 1440p; 80+ Mbps is overkill)

If frames are encoded fine on the host but late on the client, the wire is the bottleneck — there's nothing host-side that helps.

---

## When `solstream doctor` is green but you're still broken

That means we have a coverage gap in the doctor checks. Open an issue at https://github.com/mxmjxn/SolStream with:

- Output of `solstream doctor --verbose`
- `uname -a`, `lsb_release -a`, `nvidia-smi`, `gamescope --version`, `sunshine --version`
- `journalctl --user -u gamescope-sunshine.service --since "1 hour ago"`
- Description of the symptom

The fix that solves your case becomes a new doctor check.
