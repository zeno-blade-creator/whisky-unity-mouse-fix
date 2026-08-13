#!/bin/bash
# Copies your ALREADY-LOGGED-IN Steam session from the real Mac Steam into the
# Windows Steam running under Wine.
#
# WHY THIS IS THE KEY STEP
# ------------------------
# The black window has only ever blocked ONE thing: logging in. Games draw
# through a completely different, working path. So if Windows Steam starts up
# ALREADY logged in, the black login screen stops mattering.
#
# Your real Mac Steam is logged in as "glorie_us" (account ulimanut) with
# "remember password" switched on. Everything needed is already on this
# machine.
#
# WHY THE EARLIER ATTEMPT FAILED
# -------------------------------
# A session copy was tried before, from the CrossOver bottle, and Steam stayed
# logged out. Checking what is actually on disk shows two files were missing
# from the Wine copy:
#
#   registry.vdf   - says WHICH account to log in as automatically
#   ssfn...        - the Steam Guard file that says "this machine is trusted"
#
# Neither exists in the Wine Steam folder. Without them Steam has an account
# name but no proof it is allowed to use it, so it falls back to asking you to
# log in - on a screen you cannot see.
#
# WHAT THIS SCRIPT COPIES
#   registry.vdf          which account to auto-log-in
#   ssfn...               Steam Guard machine trust
#   config/               login tokens (loginusers.vdf, config.vdf)
#   userdata/             your personal settings
#
# It also writes steam.cfg with BootStrapperInhibitAll=Enable, which stops
# Steam updating itself and quietly undoing all of this.
#
# SAFETY: everything it replaces is backed up first, with a timestamp. Nothing
# is deleted. Your real Mac Steam is only ever READ FROM, never modified.

set -u

NATIVE="$HOME/Library/Application Support/Steam"
WINE_STEAM="$HOME/Games/wine-gaming/drive_c/Program Files (x86)/Steam"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==================================================="
echo "  Copy Steam login into the Wine setup"
echo "==================================================="
echo ""

if [ ! -d "$NATIVE" ]; then
  echo "ERROR: cannot find your real Mac Steam at:"
  echo "  $NATIVE"
  read -n 1; exit 1
fi
if [ ! -d "$WINE_STEAM" ]; then
  echo "ERROR: cannot find the Windows Steam at:"
  echo "  $WINE_STEAM"
  read -n 1; exit 1
fi

# Steam MUST be closed or it will overwrite these files as it exits.
if pgrep -f "steam.exe" >/dev/null 2>&1 || pgrep -f "steamwebhelper" >/dev/null 2>&1; then
  echo "Windows Steam is still running - stopping it first."
  pkill -9 -f "steamwebhelper"     2>/dev/null
  pkill -9 -f "steamservice"       2>/dev/null
  pkill -9 -f "steamerrorreporter" 2>/dev/null
  pkill -9 -f "steam.exe"          2>/dev/null
  sleep 3
  "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wineserver" -k 2>/dev/null
  sleep 2
fi

# The real Mac Steam must also be closed, so its files are not mid-write.
if pgrep -x "steam_osx" >/dev/null 2>&1; then
  echo ""
  echo "WARNING: your real Mac Steam appears to be running."
  echo "Please quit it completely, then run this again."
  echo "(Its files can be half-written while it is open.)"
  echo ""
  echo "Press any key to close."
  read -n 1; exit 1
fi

echo "Backing up what is there now (nothing is deleted)..."
for item in config userdata registry.vdf; do
  if [ -e "$WINE_STEAM/$item" ]; then
    cp -R "$WINE_STEAM/$item" "$WINE_STEAM/$item.bak-$STAMP" 2>/dev/null \
      && echo "  saved $item -> $item.bak-$STAMP"
  fi
done
echo ""

echo "Copying your login across..."

# 1. Which account to log in as, automatically.
if cp "$NATIVE/registry.vdf" "$WINE_STEAM/registry.vdf" 2>/dev/null; then
  echo "  registry.vdf      copied   <-- was MISSING before"
else
  echo "  registry.vdf      FAILED"
fi

# 2. Steam Guard "this machine is trusted" file.
SSFN_COUNT=0
for f in "$NATIVE"/ssfn*; do
  [ -e "$f" ] || continue
  cp "$f" "$WINE_STEAM/$(basename "$f")" 2>/dev/null && SSFN_COUNT=$((SSFN_COUNT + 1))
done
if [ "$SSFN_COUNT" -gt 0 ]; then
  echo "  ssfn (Steam Guard) copied $SSFN_COUNT   <-- was MISSING before"
else
  echo "  ssfn (Steam Guard) none found"
fi

# 3. Login tokens.
if cp -R "$NATIVE/config/." "$WINE_STEAM/config/" 2>/dev/null; then
  echo "  config/           copied"
else
  echo "  config/           FAILED"
fi

# 4. Personal settings.
if cp -R "$NATIVE/userdata/." "$WINE_STEAM/userdata/" 2>/dev/null; then
  echo "  userdata/         copied"
else
  echo "  userdata/         FAILED"
fi

# 5. Stop Steam updating itself and undoing this.
printf 'BootStrapperInhibitAll=Enable\n' > "$WINE_STEAM/steam.cfg"
echo "  steam.cfg         written (stops self-updates)"

echo ""
echo "  --- check -----------------------------------------------------"
ACCT=$(grep -o '"AutoLoginUser"[^"]*"[^"]*"' "$WINE_STEAM/registry.vdf" 2>/dev/null | tail -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$ACCT" ]; then
  echo "  Windows Steam will now try to log in as: $ACCT"
else
  echo "  Could not confirm the account name - tell Claude."
fi
ls "$WINE_STEAM"/ssfn* >/dev/null 2>&1 \
  && echo "  Steam Guard file is in place." \
  || echo "  Steam Guard file NOT in place - Steam may still ask to verify."
echo "  ---------------------------------------------------------------"

echo ""
echo "Done. Now run:  TEST 9 - Steam with no browser at all.command"
echo ""
echo "Press any key to close."
read -n 1
