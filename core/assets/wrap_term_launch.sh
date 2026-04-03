#!/usr/bin/env sh

cat ~/.local/state/symmetria/sequences.txt 2>/dev/null

exec "$@"
