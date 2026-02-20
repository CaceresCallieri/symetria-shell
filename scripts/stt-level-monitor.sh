#!/bin/sh
# Audio level monitor for Symmetria STT
# Reads 16kHz mono s16le from pw-record, computes RMS per 100ms chunk (~10Hz)
# Output: float 0.0-1.0 on stdout (one value per line)
# Usage: stt-level-monitor.sh

pw-record --format=s16 --rate=16000 --channels=1 - 2>/dev/null | \
    od -An -td2 -w3200 | \
    awk '{ sum=0; n=0; for(i=1;i<=NF;i++){sum+=$i*$i; n++} if(n>0) printf "%.4f\n", sqrt(sum/n)/32768; fflush() }'
