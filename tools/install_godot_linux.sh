#!/usr/bin/env bash
# Installs headless-capable Godot for Linux (CI / cloud sessions). Usage:
#   source tools/install_godot_linux.sh   -> exports $GODOT
set -euo pipefail
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
DEST="${GODOT_HOME:-$HOME/.godot-bin}"
BIN="$DEST/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  curl -sSL -o "$DEST/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -q -o "$DEST/godot.zip" -d "$DEST"
  rm "$DEST/godot.zip"
  chmod +x "$BIN"
fi
export GODOT="$BIN"
echo "GODOT=$GODOT"
