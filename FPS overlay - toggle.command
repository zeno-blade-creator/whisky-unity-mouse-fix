#!/bin/bash
# Turns the FPS overlay (Apple's Metal HUD) on or off.
#
# SCOPE: this applies to EVERY Windows game launched from this folder, not just
# one game. The overlay appears in the TOP-LEFT of the game window.
#
# WHY IT RESTARTS STEAM: the overlay is switched on by an environment variable,
# and a program only reads those when it starts. Steam also kills and relaunches
# games during startup, so the game inherits Steam's environment - which means
# Steam itself has to be restarted for the setting to reach the game.

cd "$(dirname "$0")" || exit 1
source ./config.sh

STATE_FILE="$WINEPREFIX/.hud_enabled"
mkdir -p "$WINEPREFIX"
[ -f "$STATE_FILE" ] || echo "0" > "$STATE_FILE"

if [ "$(cat "$STATE_FILE")" = "1" ]; then
  echo "0" > "$STATE_FILE"; NEW="OFF"
else
  echo "1" > "$STATE_FILE"; NEW="ON"
fi

echo "==================================================="
echo "  FPS overlay is now: $NEW"
echo "  (applies to all games launched from this folder)"
echo "==================================================="
echo ""
echo "Closing Steam so the change takes effect..."

pkill -f "steamwebhelper" 2>/dev/null
pkill -f "steam.exe" 2>/dev/null
sleep 4
"$WINESERVER" -k 2>/dev/null
sleep 2

echo "Done."
echo ""
echo "Now launch your game as usual - Steam restarts automatically."
[ "$NEW" = "ON" ] && echo "The overlay will appear in the TOP-LEFT of the game window."
echo ""
echo "Press any key to close."
read -n 1
