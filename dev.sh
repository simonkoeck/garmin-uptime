#!/usr/bin/env bash
# Hot-reload loop: rebuild Lumen and push it into the running simulator on every
# change to source/, resources/ or manifest.xml.
#
# Usage:
#   1. start the simulator once:   nix develop -c connectiq &
#   2. run this:                   ./dev.sh            (or ./dev.sh venu445mm)
#   3. edit source — the sim updates on save.
set -uo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-venu441mm}"

# Re-enter the Nix dev shell if monkeyc/watchexec aren't already on PATH.
if ! command -v monkeyc >/dev/null 2>&1 || ! command -v watchexec >/dev/null 2>&1; then
  exec nix develop -c "$0" "$@"
fi

mkdir -p bin

reload() {
  if monkeyc -d "$DEVICE" -f monkey.jungle -o bin/uptime.prg -y developer_key; then
    monkeydo bin/uptime.prg "$DEVICE" || \
      echo "!! monkeydo failed — is the simulator open? (nix develop -c connectiq &)"
  else
    echo "!! build failed — fix the error above; watching for the next save."
  fi
}

reload
echo ">> watching source/ resources/ manifest.xml — edit and save to reload (Ctrl-C to stop)"
watchexec --debounce 300ms --watch source --watch resources --watch manifest.xml -- \
  "monkeyc -d $DEVICE -f monkey.jungle -o bin/uptime.prg -y developer_key && monkeydo bin/uptime.prg $DEVICE"
