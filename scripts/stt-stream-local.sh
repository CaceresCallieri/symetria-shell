#!/usr/bin/env bash
# Launch the streaming STT helper under the faster-whisper venv with the
# bundled NVIDIA CUDA libraries (cuBLAS/cuDNN) on LD_LIBRARY_PATH.
#
# Why a wrapper: ctranslate2's pip wheel does NOT bundle cuBLAS/cuDNN, so they
# must be discoverable at load time. LD_LIBRARY_PATH is read by the dynamic
# linker at exec — it cannot be set reliably from inside the already-started
# Python process (glibc caches it). `exec` replaces this shell with the venv
# python so QML's Process manages the helper directly (which owns its own
# pw-record child) — no extra process layer, no orphan risk.
#
# Override the venv location with SYMMETRIA_STT_VENV. See
# docs/stt-streaming-spec.md for the install recipe.
set -euo pipefail

VENV="${SYMMETRIA_STT_VENV:-$HOME/.local/share/symmetria/stt-venv}"
PY="$VENV/bin/python"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$PY" ]; then
    printf '{"type":"error","detail":"faster-whisper venv not found at %s — see docs/stt-streaming-spec.md for the install recipe"}\n' "$VENV"
    exit 1
fi

# Collect the bundled NVIDIA lib dirs (cuBLAS, cuDNN, ...). The glob is robust
# to the python version and to which nvidia-* packages happen to be installed.
libdirs=""
for d in "$VENV"/lib/python*/site-packages/nvidia/*/lib; do
    [ -d "$d" ] || continue
    libdirs="${libdirs:+$libdirs:}$d"
done

export LD_LIBRARY_PATH="${libdirs}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

exec "$PY" "$SCRIPT_DIR/stt-stream.py" "$@"
