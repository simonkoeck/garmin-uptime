#!/usr/bin/env bash
# Headless screenshot of the watch face: build, run the sim under Xvfb, push the
# app, capture the simulator window to a PNG. Usage: ./shot.sh [device] [outfile]
set -uo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-venu441mm}"
OUT="${2:-/tmp/lumen-shot.png}"

nix shell .#connectiq nixpkgs#xvfb-run nixpkgs#xorg.xwininfo nixpkgs#imagemagick -c bash -c '
  set -e
  DEVICE="'"$DEVICE"'"; OUT="'"$OUT"'"
  monkeyc -d "$DEVICE" -f monkey.jungle -o bin/Lumen.prg -y developer_key
  xvfb-run -a -s "-screen 0 1500x1100x24" bash -c "
    connectiq >/tmp/sim.log 2>&1 &
    sleep 14
    monkeydo bin/Lumen.prg \"$DEVICE\" >/tmp/do.log 2>&1
    sleep 9
    xwininfo -root -tree >/tmp/tree.txt 2>&1
    # the simulator window is the largest non-root window
    WID=\$(xwininfo -root -tree 2>/dev/null | grep -oiE '0x[0-9a-f]+ .*[0-9]{3,}x[0-9]{3,}\+' | sort -t' ' -k1 | awk '{print \$1}' | head -1)
    echo \"WID=\$WID\"
    if [ -n \"\$WID\" ]; then import -window \"\$WID\" \"\$OUT\"; else import -window root \"\$OUT\"; fi
    echo CAPTURED \"\$OUT\"
  "
'
echo "--- monkeydo ---"; tail -2 /tmp/do.log 2>/dev/null
echo "--- windows ---"; grep -oiE "0x[0-9a-f]+ .*[0-9]{3,}x[0-9]{3,}\+[0-9-]+\+[0-9-]+" /tmp/tree.txt 2>/dev/null | head
