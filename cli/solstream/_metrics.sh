#!/bin/bash
# solstream metrics — capture host-side performance during a Moonlight stream.
# Called by the solstream CLI's `metrics` subcommand.
# Usage:   _metrics.sh <duration_seconds>
# Output:  ~/.solstream/metrics/<timestamp>.csv + companion .log

DUR="${1:-30}"
OUT_DIR="${HOME}/.solstream/metrics"
mkdir -p "$OUT_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
CSV="$OUT_DIR/$TS.csv"
LOG="$OUT_DIR/$TS.log"

echo "ts,gpu_util,gpu_mem_used_MiB,gpu_enc_util,gpu_temp_C,sm_clock_MHz,host_load1,steam_cpu_pct,sunshine_cpu_pct" > "$CSV"
{
  echo "=== capture-stream-metrics.sh ==="
  echo "duration=${DUR}s  out=$CSV"
  echo "system: $(uname -r) — $(uptime -p)"
  echo "nvidia-smi banner:"
  nvidia-smi --query-gpu=name,driver_version,vbios_version,memory.total,utilization.gpu,utilization.memory --format=csv
  echo
} >> "$LOG" 2>&1

END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
  TS_NOW=$(date +%s.%3N)
  read -r G_UTIL G_MEM G_ENC G_TEMP G_CLK < <(
    nvidia-smi --query-gpu=utilization.gpu,memory.used,utilization.encoder,temperature.gpu,clocks.sm \
               --format=csv,noheader,nounits | tr ',' ' '
  )
  LOAD1=$(cut -d' ' -f1 < /proc/loadavg)
  # Steam / sunshine CPU% — sample via top in batch mode (one-shot)
  STEAM_CPU=$(top -bn1 -p "$(pgrep -d, -f 'ubuntu12_32/steam$' | head -1)" 2>/dev/null \
              | awk 'NR==8 {print $9}')
  SUN_CPU=$(top -bn1 -p "$(pgrep -d, -f '^/usr/bin/sunshine$' | head -1)" 2>/dev/null \
              | awk 'NR==8 {print $9}')
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$TS_NOW" "$G_UTIL" "$G_MEM" "$G_ENC" "$G_TEMP" "$G_CLK" \
    "$LOAD1" "${STEAM_CPU:-0}" "${SUN_CPU:-0}" >> "$CSV"
  sleep 0.5
done

{
  echo
  echo "=== Summary ==="
  echo "rows captured: $(($(wc -l < "$CSV") - 1))"
  echo "gpu_util  min/avg/max: $(awk -F, 'NR>1{n++;s+=$2;if($2<mn||!mn)mn=$2;if($2>mx)mx=$2}END{printf "%s/%.1f/%s\n",mn,s/n,mx}' "$CSV")"
  echo "gpu_enc   min/avg/max: $(awk -F, 'NR>1{n++;s+=$4;if($4<mn||!mn)mn=$4;if($4>mx)mx=$4}END{printf "%s/%.1f/%s\n",mn,s/n,mx}' "$CSV")"
  echo "load1     min/avg/max: $(awk -F, 'NR>1{n++;s+=$7;if($7<mn||!mn)mn=$7;if($7>mx)mx=$7}END{printf "%s/%.2f/%s\n",mn,s/n,mx}' "$CSV")"
} >> "$LOG"

echo "wrote: $CSV"
echo "       $LOG"
tail -10 "$LOG"
