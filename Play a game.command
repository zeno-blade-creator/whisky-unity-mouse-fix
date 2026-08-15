#!/bin/bash
# Launches a Steam game in Whisky, repairing the two things that reliably break
# it first. Double-click this file.
#
# The first time you run it, it asks for the game's Steam App ID and remembers
# it in game.conf. After that it just launches.
#
#
# WHAT IT REPAIRS, AND WHY IT HAS TO
# ----------------------------------
# 1. THE GRAPHICS LAYER.  Whisky switches Direct3D translators by copying files
#    into your bottle, but its two packages contain different numbers of files
#    and nothing removes the old ones. Launching a game from Whisky itself can
#    therefore leave a half-and-half set that cannot start a game, failing with
#    "failed to create device and context (80004005)" - which looks nothing like
#    a graphics problem. config.sh's ensure_dxmt() puts it back.
#
# 2. THE SAVED SCREEN SIZE.  On a Retina Mac, macOS reports the screen as
#    smaller than it physically is (e.g. 1470x956 when it is really 2560x1664).
#    Unity saves that fake size. Wine then checks it against REAL display modes,
#    finds nothing matching, and refuses to start:
#
#        Couldn't switch to requested monitor resolution
#
#    Worse, the bad value persists, so every future launch fails the same way.
#
#    The fix is to DELETE the saved size rather than write a new one. Unity's
#    borderless fullscreen means "use the display's native resolution", so with
#    nothing saved it asks for a size that always exists - on any monitor, on
#    any Mac. No hardcoded numbers.
#
# Your fullscreen preference, volume, keybinds and graphics settings are all
# left alone. Only "exclusive fullscreen" is switched to borderless, because
# that is the one mode that demands a real display-mode change and can fail.

set -u
cd "$(dirname "$0")" || exit 1
source ./config.sh
wine_check || { echo ""; echo "Press any key to close."; read -n 1; exit 1; }

GAME_CONF="./game.conf"

echo "==================================================="
echo "  Play a game"
echo "==================================================="
echo ""

# --- which game? ------------------------------------------------------------
APPID=""
[ -f "$GAME_CONF" ] && APPID=$(grep -v '^#' "$GAME_CONF" | head -1 | tr -dc '0-9')

if [ -z "$APPID" ]; then
  echo "Which game? I need its Steam App ID."
  echo ""
  echo "To find it: open the game's page on store.steampowered.com and look at"
  echo "the address bar. The number after /app/ is the App ID."
  echo "  https://store.steampowered.com/app/3527290/PEAK/"
  echo "                                     ^^^^^^^ this part"
  echo ""
  printf "App ID: "
  read -r APPID
  APPID=$(echo "$APPID" | tr -dc '0-9')
  [ -z "$APPID" ] && { echo "That wasn't a number. Nothing done."; echo "Press any key."; read -n 1; exit 1; }
  echo "$APPID" > "$GAME_CONF"
  echo "  saved - it won't ask again. Delete game.conf to change it."
fi
echo "  Game: Steam App ID $APPID"
echo "  Bottle: $(basename "$WINEPREFIX")"
echo ""

# --- stop anything left over ------------------------------------------------
echo "Clearing anything still running..."
pgrep -x Whisky >/dev/null && osascript -e 'tell application "Whisky" to quit' 2>/dev/null
sleep 2
for p in "UnityCrashHandler" "steamwebhelper" "steamerrorreporter" "steamservice" "steam.exe" "conhost.exe"; do
  pkill -9 -if "$p" 2>/dev/null
done
pkill -9 -x winedbg 2>/dev/null
sleep 2
"$WINESERVER" -k 2>/dev/null
sleep 2

# --- repair the graphics layer ----------------------------------------------
ensure_dxmt

# --- repair the remembered display settings ---------------------------------
# Unity stores these per game under Software\<Publisher>\<Game>, and appends a
# hash to every setting name that differs per title - so both the game and the
# exact key names are discovered from the registry rather than hardcoded. That
# is what makes this work for any Unity game, not just the one it was written
# for.
REG="$WINEPREFIX/user.reg"
if [ -f "$REG" ]; then
  cp -p "$REG" "$REG.bak-play-$(date +%Y%m%d-%H%M%S)" 2>/dev/null

  CLEARED=$(python3 - "$REG" <<'PY'
import re, sys
path = sys.argv[1]
src  = open(path, encoding='utf-8', errors='surrogateescape').read()

# Delete every saved pixel dimension, for every Unity game in this bottle.
new, n = re.subn(r'^"Screenmanager Resolution (?:Width|Height)[^"]*"=dword:[0-9a-f]+\n',
                 '', src, flags=re.M)

# Exclusive fullscreen (mode 0) is the only mode that demands a real display
# mode change and can therefore fail. Switch it to borderless (1), which looks
# identical and cannot fail. Any other preference is left untouched.
new, m = re.subn(r'^("Screenmanager Fullscreen mode[^"]*"=dword:)00000000$',
                 r'\g<1>00000001', new, flags=re.M)

if n or m:
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
print(f"{n} {m}")
PY
)
  set -- $CLEARED
  if [ "${1:-0}" != "0" ]; then
    echo "  cleared ${1} saved screen size(s) so the game uses your real screen"
  else
    echo "  no saved screen size to clear (fine - nothing was stuck)"
  fi
  [ "${2:-0}" != "0" ] && echo "  switched exclusive fullscreen -> borderless (cannot fail)"
fi

sleep 1
"$WINESERVER" -k 2>/dev/null
sleep 2

# --- launch -----------------------------------------------------------------
echo ""
echo "Starting Steam and launching the game..."
echo "(Steam takes a moment to start before the game appears.)"
echo ""
"$WINE" "$STEAM_EXE" -applaunch "$APPID" >/tmp/whisky-game-launch.log 2>&1

echo ""
echo "Game/Steam exited."
echo ""

# --- report what the game itself said ---------------------------------------
# Reading the game's own log is the difference between "it didn't work" and
# knowing why. Unity writes one per game; find whichever changed most recently.
LOGDIR="$WINEPREFIX/drive_c/users/$USER/AppData/LocalLow"
PLAYER_LOG=$(find "$LOGDIR" -name "Player.log" -newermt "-2 hours" 2>/dev/null | head -1)
if [ -n "$PLAYER_LOG" ]; then
  echo "--- what the game reported about graphics ---"
  grep -m8 -E "Initialize engine version|d3d1[12]:|Vulkan detection|Failed to initialize graphics|Couldn't switch to requested|could not switch resolution" \
    "$PLAYER_LOG" | sed 's/^/  /'
  if grep -q "Failed to initialize graphics" "$PLAYER_LOG"; then
    echo ""
    echo "  => The graphics layer failed. Run 'FIX graphics stack.command'."
  elif grep -q "Couldn't switch to requested monitor resolution" "$PLAYER_LOG"; then
    echo ""
    echo "  => Resolution problem, not a graphics-layer problem."
  else
    echo ""
    echo "  => No graphics failure recorded."
  fi
  echo "  full log: $PLAYER_LOG"
  echo "---------------------------------------------"
  echo ""
fi

echo "If anything went wrong, run 'STOP everything.command' and try again."
echo "Press any key to close."
read -n 1
