#!/bin/bash
# solstream-game-shutdown.sh
#
# Kill the currently-running Steam game, leaving Steam itself + the
# gamescope session up. Designed to be invoked from a Sunshine app
# launcher tile so users can quit games from their Moonlight client
# without having to navigate the game's own UI.
#
# Process tree Steam builds for a launched game:
#   steam (main)
#     └── reaper SteamLaunch AppId=N -- ...
#           └── pressure-vessel-wrap ...
#                 └── pv-adverb ...
#                       └── srt-logger ...
#                             └── <game executable>
#
# Sending SIGTERM to the topmost reaper cascades cleanly: Steam sees the
# child exit, marks the game as stopped, and the game gets a chance to
# save state before dying. SIGKILL fallback after 8s for hung titles.

set -u

LOG="/tmp/solstream-game-shutdown.log"
# Keep last ~100 entries
[ -f "$LOG" ] && tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG" || true
exec >> "$LOG" 2>&1

echo "=== invoked at $(date -u +%FT%TZ) by uid=$(id -u) ==="

# ─── Find the game launcher ─────────────────────────────────────────────
# Pattern matches `reaper SteamLaunch AppId=N -- /game/binary args...`.
# This is the topmost process specific to the running game; killing it
# cascades down.
REAPER_PIDS=$(pgrep -f "reaper SteamLaunch" 2>/dev/null || true)

# Fallback: some older/newer Steam runtimes use slightly different wrapper
# naming. pressure-vessel-wrap is also a Steam-spawned process tree root.
if [ -z "$REAPER_PIDS" ]; then
  REAPER_PIDS=$(pgrep -f "pressure-vessel-wrap" 2>/dev/null || true)
fi

if [ -z "$REAPER_PIDS" ]; then
  echo "no game running (no reaper SteamLaunch or pressure-vessel-wrap pids)"
  echo "nothing to do — Steam Big Picture itself is left alone"
  exit 0
fi

echo "game reaper pids: $REAPER_PIDS"

# ─── Step 1: graceful SIGTERM ──────────────────────────────────────────
for pid in $REAPER_PIDS; do
  comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
  args=$(ps -p "$pid" -o args= 2>/dev/null || echo "?")
  echo "  SIGTERM -> pid=$pid  comm=$comm  args=${args:0:200}"
  kill -TERM "$pid" 2>/dev/null || echo "    (kill -TERM returned $?)"
done

# ─── Step 2: wait up to 8s for graceful exit ───────────────────────────
for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  REMAINING=$(pgrep -f "reaper SteamLaunch" 2>/dev/null || true)
  REMAINING="$REMAINING $(pgrep -f "pressure-vessel-wrap" 2>/dev/null || true)"
  REMAINING=$(echo "$REMAINING" | tr -s ' ' | sed 's/^ //;s/ $//')
  if [ -z "$REMAINING" ]; then
    echo "graceful shutdown complete after ${i}s"
    exit 0
  fi
done

# ─── Step 3: SIGKILL ───────────────────────────────────────────────────
echo "SIGTERM didn't take after 8s, escalating to SIGKILL"
for pid in $REAPER_PIDS; do
  if kill -0 "$pid" 2>/dev/null; then
    echo "  SIGKILL -> pid=$pid"
    kill -KILL "$pid" 2>/dev/null || true
  fi
done

# Also nuke any stray pressure-vessel-wrap that lost its parent
pkill -KILL -f "pressure-vessel-wrap" 2>/dev/null || true

sleep 1
FINAL=$(pgrep -f "reaper SteamLaunch|pressure-vessel-wrap" 2>/dev/null || true)
if [ -n "$FINAL" ]; then
  echo "warning: pids still alive after SIGKILL: $FINAL"
  exit 1
fi
echo "SIGKILL cleanup complete"
exit 0
