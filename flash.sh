#!/usr/bin/env bash
# Build the Lumen watch face and flash it to a USB-connected Garmin watch.
#
#   ./flash.sh                 # build for venu441mm and copy to the watch
#   ./flash.sh venu445mm       # build for a different device id
#
# Requirements:
#   * watch plugged in, awake/unlocked, USB Mode = MTP
#     (Settings > System > USB Mode > MTP on the watch — "Garmin" mode won't work)
#   * gvfs with the MTP backend (system already has services.gvfs.enable = true)
#   * the Nix dev shell from ./flake.nix (provides monkeyc) and a developer_key
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${1:-venu441mm}"
PRG="bin/uptime.prg"

if [ ! -f developer_key ]; then
  echo "ERROR: developer_key not found. Generate it once inside 'nix develop':" >&2
  echo "  openssl genrsa -out developer_key.pem 4096 && \\" >&2
  echo "  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key -nocrypt" >&2
  exit 1
fi

echo ">> Building $PRG for $DEVICE ..."
mkdir -p bin
nix develop -c monkeyc -d "$DEVICE" -f monkey.jungle -o "$PRG" -y developer_key

# Find the watch's MTP volume (activation_root=mtp://091e_xxxx_yyyy/). The id
# changes between reconnects, so always detect it fresh.
echo ">> Looking for an MTP watch ..."
URI="$(gio mount -li 2>/dev/null | grep -oiE 'mtp://[a-z0-9_]+/' | head -1 || true)"
if [ -z "$URI" ]; then
  echo "ERROR: no MTP device found." >&2
  echo "  Wake/unlock the watch, set USB Mode to MTP (Settings > System > USB Mode)," >&2
  echo "  then replug and re-run. Current USB devices:" >&2
  gio mount -li 2>/dev/null | grep -i mtp >&2 || echo "  (no mtp volumes listed)" >&2
  exit 1
fi
echo "   found $URI"

# Mount it (ignore "already mounted").
gio mount "$URI" 2>/dev/null || true

# The first listed entry is the storage name, e.g. "Internal Storage".
STORAGE="$(gio list "$URI" 2>/dev/null | head -1)"
if [ -z "$STORAGE" ]; then
  echo "ERROR: could not read watch storage (is it awake?)." >&2
  exit 1
fi

DEST="${URI}${STORAGE}/GARMIN/Apps/$(basename "$PRG")"
echo ">> Copying to $DEST"
gio copy -p "$PRG" "$DEST"

echo ">> Unmounting ..."
gio mount -u "$URI" 2>/dev/null || true

echo
echo "Done. Unplug the watch, then pick 'uptime' from the watch-face list."
echo "(On music watches the file vanishes from GARMIN/Apps after unplug — that's"
echo " normal; it moved to protected storage, meaning it installed.)"
