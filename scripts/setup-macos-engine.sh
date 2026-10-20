#!/usr/bin/env bash
# For development: sets up the macOS engine from the terminal using your own
# python3. The app can do this itself (Install button), with a bundled Python.
set -euo pipefail

ENGINE_DIR="$HOME/Library/Application Support/Snag/engine/python"
PYTHON="${PYTHON:-python3}"

if [ ! -x "$ENGINE_DIR/bin/python3" ]; then
  echo "Creating environment in $ENGINE_DIR"
  mkdir -p "$(dirname "$ENGINE_DIR")"
  "$PYTHON" -m venv "$ENGINE_DIR"
fi

"$ENGINE_DIR/bin/python3" -m pip install --upgrade --quiet pip
"$ENGINE_DIR/bin/python3" -m pip install --upgrade yt-dlp gallery-dl

echo
echo "Engine ready:"
"$ENGINE_DIR/bin/python3" -c 'import yt_dlp, gallery_dl; print("  yt-dlp", yt_dlp.version.__version__); print("  gallery-dl", gallery_dl.version.__version__)'
echo
echo "Try it: \"$ENGINE_DIR/bin/python3\" Snag/Engine/snag_bridge.py <post url>"
