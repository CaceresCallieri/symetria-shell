#!/bin/sh
set -eu
# Audio level monitor for Symmetria STT
# Reads 16kHz mono s16le from pw-record, computes RMS per 100ms chunk (~10Hz)
# Output: float 0.0-1.0 on stdout (one value per line)
# Usage: stt-level-monitor.sh [pipewire-source-node-name]
#   Optional arg: PipeWire node to monitor (pw-record --target).
#   Empty/omitted = system default source.

command -v pw-record >/dev/null 2>&1 || {
    echo "Error: required command 'pw-record' not found (install pipewire)" >&2
    exit 1
}

TARGET="${1:-}"
set --
[ -n "$TARGET" ] && set -- "--target=$TARGET"

pw-record --format=s16 --rate=16000 --channels=1 "$@" - 2>/dev/null | \
    od -An -td2 -w3200 | \
    awk '{ if(NF < 100) next; sum=0; n=0; for(i=1;i<=NF;i++){sum+=$i*$i; n++} if(n>0) printf "%.4f\n", sqrt(sum/n)/32768; fflush() }'
