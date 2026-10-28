#!/usr/bin/env bash
# Fetch doomgeneric (GPL-2.0, https://github.com/ozkl/doomgeneric) at a pinned commit.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
COMMIT=e257a09527062bfb986b6e5e0780839b6cbd5b71
if [ ! -d "$HERE/doomgeneric/.git" ]; then
  git clone -q https://github.com/ozkl/doomgeneric "$HERE/doomgeneric"
fi
git -C "$HERE/doomgeneric" checkout -q "$COMMIT"
echo "doomgeneric at $COMMIT"
