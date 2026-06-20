#!/usr/bin/env bash
# Serve the repo over local HTTP so Roblox Studio can pull sources directly when the
# Rojo plugin isn't connected (the code-sync fallback — see scripts/studio-sync.luau).
# Studio's HttpService can reach 127.0.0.1. Ctrl-C to stop.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Serving $(pwd) at http://127.0.0.1:8777"
echo "Now paste scripts/studio-sync.luau into the Studio command bar (Edit mode)."
exec python3 -m http.server 8777 --bind 127.0.0.1
