#!/bin/bash
# Installs a Windows Steam game and creates a double-click launcher for it.
#
# All you need is the game's Steam App ID. If you don't know what that is or
# where to find it, this script explains it and walks you through.

cd "$(dirname "$0")" || exit 1
source ./config.sh
FOLDER="$(pwd)"
wine_check || { echo ""; echo "Press any key to close."; read -n 1; exit 1; }

clear
echo "==================================================="
echo "  Add a Windows game"
echo "==================================================="
echo ""
echo "I need the game's STEAM APP ID - the number Steam uses to identify it."
echo ""
echo "HOW TO FIND IT (30 seconds):"
echo ""
echo "  1. Go to the game's page on the Steam website"
echo "     (or in Steam, right-click the game > Manage > Store page)"
echo ""
echo "  2. Look at the address bar. The URL looks like:"
echo ""
echo "       store.steampowered.com/app/3527290/PEAK/"
echo "                                  ^^^^^^^"
echo "                                  this number"
echo ""
echo "  3. That number is the App ID. For PEAK it's 3527290."
echo ""
echo "  Can't find the store page? Google:  <game name> steam app id"
echo ""
echo "---------------------------------------------------"
echo ""
printf "Paste the App ID here (or press Enter to cancel): "
read -r APPID

[ -z "$APPID" ] && { echo "Cancelled."; exit 0; }

if ! echo "$APPID" | grep -qE '^[0-9]+$'; then
  echo ""
  echo "That doesn't look like an App ID - it should be digits only, e.g. 3527290."
  echo "Press any key to close, then try again."
  read -n 1; exit 1
fi

# Look the game up so we can name things properly and warn about Mac-native titles.
echo ""
echo "Looking up App ID $APPID on Steam..."
INFO=$(curl -s --max-time 20 "https://store.steampowered.com/api/appdetails?appids=$APPID&filters=basic,platforms" 2>/dev/null)
NAME=$(echo "$INFO" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); v=d[list(d)[0]]
    print(v['data']['name'] if v.get('success') else '')
except Exception: print('')
" 2>/dev/null)
WINDOWS=$(echo "$INFO" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); v=d[list(d)[0]]
    print('yes' if v.get('success') and v['data'].get('platforms',{}).get('windows') else 'no')
except Exception: print('unknown')
" 2>/dev/null)

if [ -z "$NAME" ]; then
  echo "  Couldn't look that ID up. It may be wrong, or Steam may be unreachable."
  printf "  Continue anyway? [y/N]: "
  read -r GO
  [ "$GO" != "y" ] && { echo "Cancelled."; exit 0; }
  NAME="Game $APPID"
else
  echo "  Found: $NAME"
  [ "$WINDOWS" = "no" ] && echo "  NOTE: Steam says this has no Windows build - that would be unusual here."
fi

MANIFEST="$STEAMAPPS/appmanifest_$APPID.acf"

# Already installed? Then this is someone re-running the script to regenerate a
# launcher (or to get one for a game they installed through Steam directly).
# Skip straight to creating it rather than starting Steam and waiting on a
# download that already happened.
ALREADY=0
if [ -f "$MANIFEST" ] && [ "$(grep -m1 '"StateFlags"' "$MANIFEST" | tr -dc '0-9')" = "4" ]; then
  ALREADY=1
  echo ""
  echo "  \"$NAME\" is already installed - just creating the launcher."
fi

if [ "$ALREADY" = "0" ]; then

echo ""
ensure_steam

echo ""
echo "Telling Steam to install \"$NAME\"..."
echo "(If Steam shows an install dialog, click through it.)"
nohup "$WINE" "$STEAM_EXE" "steam://install/$APPID" >/dev/null 2>&1 &

echo ""
echo "Waiting for the download. Large games can take a while - leave this open."
echo "(Press Ctrl-C to stop waiting; the download continues in Steam regardless.)"
echo ""

DONE=0
for i in $(seq 1 720); do   # up to ~2 hours
  if [ -f "$MANIFEST" ]; then
    SF=$(grep -m1 '"StateFlags"' "$MANIFEST" | tr -dc '0-9')
    DL=$(grep -m1 '"BytesDownloaded"' "$MANIFEST" | tr -dc '0-9')
    TOT=$(grep -m1 '"BytesToDownload"' "$MANIFEST" | tr -dc '0-9')
    if [ "$SF" = "4" ]; then DONE=1; break; fi
    if [ -n "$TOT" ] && [ "${TOT:-0}" -gt 0 ] 2>/dev/null; then
      printf "\r  %s MB / %s MB   " "$((DL/1048576))" "$((TOT/1048576))"
    else
      printf "\r  waiting for download to start...   "
    fi
  else
    printf "\r  waiting for Steam to accept the install...   "
  fi
  sleep 10
done
echo ""

if [ "$DONE" != "1" ]; then
  echo ""
  echo "The install hasn't finished yet. That's fine - it keeps going in Steam."
  echo "Re-run this script with the same App ID once it's done and it will"
  echo "create the launcher."
  echo ""
  echo "Press any key to close."; read -n 1; exit 0
fi

echo "  Installed."

fi   # end of "not already installed"

# Find the game's .exe. Prefer one matching the install directory name.
INSTALLDIR=$(grep -m1 '"installdir"' "$MANIFEST" | sed 's/.*"installdir"[^"]*"\(.*\)"/\1/')
GAMEDIR="$STEAMAPPS/common/$INSTALLDIR"
EXE=$(find "$GAMEDIR" -maxdepth 2 -iname "*.exe" 2>/dev/null \
      | grep -v -i "unins\|crash\|redist\|vcredist\|dxsetup\|setup\|launcher_" \
      | head -1)

SAFE=$(echo "$NAME" | tr -d '/:\\')
LAUNCHER="$FOLDER/Play $SAFE.command"

# Launch through Steam rather than the .exe directly. Steam relaunches the game
# through itself anyway, and going via Steam means achievements, friends and the
# overlay all work. The .exe is only used to confirm the install looks sane.
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/bin/bash
# Launches $NAME (Steam App ID $APPID).
#
# Auto-generated by "Add a game.command". Safe to delete if you uninstall the
# game - it holds no state, just the App ID above.
#
# Before starting, this repairs the two things that reliably break a game in
# Whisky. Both are explained in ../Software/FINDINGS.md:
#
#   1. The Direct3D layer, which Whisky can leave half-and-half when it launches
#      a game itself - the game then dies at startup with "failed to create
#      device and context (80004005)", which looks like anything but a graphics
#      problem.
#   2. The saved screen size, which on a Retina Mac can be a size the display
#      cannot actually produce, making the game refuse to start forever.

set -u
cd "\$(dirname "\$0")" || exit 1
source ./config.sh
wine_check || { echo ""; echo "Press any key to close."; read -n 1; exit 1; }

echo "==================================================="
echo "  $NAME"
echo "==================================================="
echo ""
echo "  Bottle: \$(basename "\$WINEPREFIX")"
echo ""

echo "Clearing anything still running..."
stop_everything

echo "Checking the graphics layer..."
ensure_dxmt

echo "Checking the saved screen size..."
clear_saved_resolution

"\$WINESERVER" -k 2>/dev/null
sleep 2

echo ""
echo "Starting Steam and launching $NAME..."
echo "(Steam takes a moment to start before the game appears.)"
echo ""
"\$WINE" "\$STEAM_EXE" -applaunch $APPID >/tmp/whisky-launch-$APPID.log 2>&1

echo ""
echo "$NAME/Steam exited."
echo ""
report_game_log

echo "If anything went wrong, run 'STOP everything.command' and try again."
echo "Press any key to close."
read -n 1
LAUNCHER_EOF

chmod +x "$LAUNCHER"

echo ""
echo "==================================================="
echo "  Done!"
echo "==================================================="
echo ""
echo "  Created:  Play $SAFE.command"
echo "  It's in this folder. Double-click it to play."
echo ""
echo "  Tip: drag it to your Dock for one-click access."
echo ""
echo "Press any key to close."
read -n 1
