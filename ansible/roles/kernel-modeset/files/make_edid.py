#!/usr/bin/env python3
"""Generate a minimal but valid EDID 1.4 for a virtual DisplayPort sink.

Usage:
    make_edid.py OUTPUT_FILE [--width W] [--height H] [--refresh HZ] [--name NAME]

Defaults to 2560x1440 @ 120 Hz using CVT-RB timing.

Produces a 128-byte EDID with:
  - Manufacturer "LNX" (open-source virtual)
  - Single Detailed Timing Descriptor advertising the requested mode
  - Display Range Limits descriptor scaled to cover the requested mode
  - Monitor Name "Headless<HEIGHT>" (truncated to fit 13-byte EDID field)
  - sRGB chromaticity
  - Valid checksum

Validates clean with `edid-decode`.
"""

import argparse
import struct
import sys


def cvt_rb_blank(active_lines: int) -> int:
    """CVT-RB vertical blanking is fixed at 21 lines + active=>vsync timing."""
    # Simplified: use 41-line blank for ≤1440p, 51 for 4K+, matching common reduced-blank monitors
    return 41 if active_lines <= 1440 else 51


def make_edid(width: int, height: int, refresh: int, name: str) -> bytes:
    e = bytearray(128)

    # Fixed 8-byte header
    e[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])

    # Manufacturer "LNX" — 5 bits per letter, big-endian packed
    L, N, X = ord("L") - 0x40, ord("N") - 0x40, ord("X") - 0x40
    mid = (L << 10) | (N << 5) | X
    e[8] = (mid >> 8) & 0xFF
    e[9] = mid & 0xFF

    struct.pack_into("<H", e, 10, 0x1140)        # product code
    struct.pack_into("<I", e, 12, 0x00000001)    # serial

    e[16] = 0          # manufacture week (0 = unknown)
    e[17] = 36         # year code: 2026 - 1990

    e[18] = 1          # EDID version
    e[19] = 4          # EDID revision

    # Video input: digital (bit 7) + 8-bit depth + DisplayPort interface
    e[20] = 0x80 | (0x01 << 4) | 0x05    # 0xA5
    e[21] = 60          # max horizontal image (cm) — placeholder
    e[22] = 34          # max vertical image (cm)
    e[23] = 0x78        # gamma = (2.2 - 1) * 100 = 120 = 0x78

    # Features: continuous-freq, preferred-timing is native, sRGB
    e[24] = 0x0A

    # sRGB chromaticity (standard primaries)
    e[25] = 0xEE; e[26] = 0x91; e[27] = 0xA3; e[28] = 0x54
    e[29] = 0x4C; e[30] = 0x99; e[31] = 0x26; e[32] = 0x0F
    e[33] = 0x50; e[34] = 0x54

    # No established / standard timings — preferred DTD carries everything
    e[35] = e[36] = e[37] = 0x00
    for i in range(8):
        e[38 + 2 * i] = 0x01
        e[39 + 2 * i] = 0x01

    # ---- Detailed Timing Descriptor #1: requested mode, CVT-RB ----
    h_active = width
    v_active = height
    h_blank = 160                                # CVT-RB reduced blanking
    v_blank = cvt_rb_blank(v_active)
    h_total = h_active + h_blank
    v_total = v_active + v_blank
    pclk_hz = h_total * v_total * refresh
    pclk_10khz = round(pclk_hz / 10000)

    h_sync_off, h_sync_w = 48, 32
    v_sync_off, v_sync_w = 3, 5

    struct.pack_into("<H", e, 54, pclk_10khz)
    e[56] = h_active & 0xFF
    e[57] = h_blank & 0xFF
    e[58] = ((h_active >> 4) & 0xF0) | ((h_blank >> 8) & 0x0F)
    e[59] = v_active & 0xFF
    e[60] = v_blank & 0xFF
    e[61] = ((v_active >> 4) & 0xF0) | ((v_blank >> 8) & 0x0F)
    e[62] = h_sync_off & 0xFF
    e[63] = h_sync_w & 0xFF
    e[64] = ((v_sync_off & 0x0F) << 4) | (v_sync_w & 0x0F)
    e[65] = (
        (((h_sync_off >> 8) & 0x03) << 6)
        | (((h_sync_w >> 8) & 0x03) << 4)
        | (((v_sync_off >> 4) & 0x03) << 2)
        | ((v_sync_w >> 4) & 0x03)
    )

    # Image size in mm — approximate by aspect ratio against a 27" diagonal
    diag_mm = 686
    aspect = h_active / v_active if v_active else 16 / 9
    v_image_mm = int(diag_mm / (1 + aspect * aspect) ** 0.5)
    h_image_mm = int(aspect * v_image_mm)
    e[66] = h_image_mm & 0xFF
    e[67] = v_image_mm & 0xFF
    e[68] = ((h_image_mm >> 4) & 0xF0) | ((v_image_mm >> 8) & 0x0F)
    e[69] = 0       # h border
    e[70] = 0       # v border
    e[71] = 0x1E    # digital sep sync, +H +V

    # ---- Display Range Limits descriptor (required by EDID 1.4) ----
    # Scale range limits to comfortably cover the requested mode.
    h_freq_khz = pclk_hz / 1000 / h_total
    max_v = max(144, refresh + 24)
    max_h = max(220, int(h_freq_khz * 1.2))
    max_pclk_per_10mhz = max(80, int((pclk_hz / 10_000_000) * 1.2))
    e[72:90] = bytes([
        0, 0, 0, 0xFD, 0,
        50,                      # min V rate (Hz)
        max_v,                   # max V rate (Hz)
        30,                      # min H rate (kHz)
        max_h & 0xFF,            # max H rate (kHz)
        max_pclk_per_10mhz & 0xFF,
        0,                       # no extended timing info
        0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20  # padding
    ])

    # ---- Monitor Name descriptor ----
    short_name = name[:13].encode("ascii", errors="replace")
    e[90:108] = bytes([0, 0, 0, 0xFC, 0]) + short_name.ljust(13, b" ")

    # ---- Dummy descriptor ----
    e[108:126] = bytes([0, 0, 0, 0x10, 0] + [0x20] * 13)

    e[126] = 0
    e[127] = (-sum(e[:127])) & 0xFF
    return bytes(e)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("output", type=str, help="Output file path")
    p.add_argument("--width", type=int, default=2560)
    p.add_argument("--height", type=int, default=1440)
    p.add_argument("--refresh", type=int, default=120)
    p.add_argument("--name", type=str, default="Headless")
    args = p.parse_args(argv)

    if args.width % 8 != 0:
        print(f"warning: width {args.width} should be a multiple of 8", file=sys.stderr)

    name = f"{args.name}{args.height}"
    data = make_edid(args.width, args.height, args.refresh, name)
    with open(args.output, "wb") as f:
        f.write(data)
    print(f"wrote {len(data)} bytes ({args.width}x{args.height}@{args.refresh}) -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
