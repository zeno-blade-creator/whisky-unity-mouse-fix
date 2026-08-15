#!/bin/bash
# Opens Windows Steam. Double-click this any time you want Steam.
# You can close the Terminal window straight away - Steam keeps running.

cd "$(dirname "$0")" || exit 1
source ./config.sh
wine_check || { echo ""; echo "Press any key to close."; read -n 1; exit 1; }

echo "==================================================="
echo "  Windows Steam"
echo "==================================================="
echo ""

# Repair the Direct3D layer if Whisky overwrote it. Skipping this is how you
# get a black Steam window with no clue as to why.
ensure_dxmt
echo ""

ensure_steam

echo ""
echo "Steam is open. You can close this window."
echo ""
echo "First time only: log in with your normal Steam account."
echo "Steam remembers you afterwards."
