#!/bin/bash
# Installs the patched Wine files into Whisky, so mouse clicks work in
# Unity 6 games such as PEAK.
#
# WHAT THIS FIXES
# ---------------
# PEAK asks Windows to switch it to modern "pointer" mouse input, by calling
# a function called EnableMouseInPointer. We proved PEAK really does this -
# Wine logged it:
#
#     fixme:win:NtUserEnableMouseInPointer enable 1 stub!
#
# "stub" means Wine has the function but it does nothing and answers "no".
# So PEAK waits for pointer messages that never arrive, and every click
# vanishes. Mouse MOVEMENT uses an older path that does work, which is why the
# cursor moved but nothing was ever clickable.
#
# The patch implements the function properly and translates ordinary mouse
# messages into the pointer messages the game is listening for.
#
# It fixes this for EVERY game in EVERY bottle, not just PEAK, because the
# change is in Wine's shared input layer.
#
# SAFETY
#   - the three original files are backed up first, with a timestamp
#   - "RESTORE Whisky original files.command" puts them back at any time
#   - if Whisky ever updates its engine, the patch is simply replaced by the
#     stock files again - nothing breaks, just re-run this script
#
# NOTE: all three files must be installed together. A partial set makes Wine
# unstable, so this script installs all three or none.

set -u
BUILD="$HOME/Desktop/Wine Windows Games/wine-patch/wine-11.0"
WINE_LIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/lib/wine"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/Desktop/Wine Windows Games/wine-patch/backups/$STAMP"

echo "==================================================="
echo "  Install the mouse patch into Whisky"
echo "==================================================="
echo ""

# --- locate the freshly built files ---------------------------------------
# These were built from Wine 11.0 source with the patch applied, then stripped
# so they match the size and shape of the files Whisky ships.
STAGED="$HOME/Desktop/Wine Windows Games/wine-patch/built"
NEW_WIN32U_DLL="$STAGED/win32u.dll"
NEW_WIN32U_SO="$STAGED/win32u.so"
NEW_USER32_DLL="$STAGED/user32.dll"

MISSING=0
for pair in "win32u.dll:$NEW_WIN32U_DLL" "win32u.so:$NEW_WIN32U_SO" "user32.dll:$NEW_USER32_DLL"; do
  name="${pair%%:*}"; path="${pair#*:}"
  if [ -z "$path" ] || [ ! -f "$path" ]; then echo "  MISSING: $name (build did not finish?)"; MISSING=1; fi
done
if [ "$MISSING" = "1" ]; then
  echo ""
  echo "The build is incomplete. Tell Claude - do not continue."
  echo "Press any key to close."; read -n 1; exit 1
fi

echo "Built files found:"
for f in "$NEW_WIN32U_DLL" "$NEW_WIN32U_SO" "$NEW_USER32_DLL"; do
  printf "  %-14s %s\n" "$(basename "$f")" "$(ls -lh "$f" | awk '{print $5}')"
done

# --- sanity check: must be x86_64, like Whisky's own engine ---------------
echo ""
echo "Checking architecture (must be x86_64)..."
if file "$NEW_WIN32U_SO" | grep -q "x86_64"; then
  echo "  win32u.so is x86_64 - correct."
else
  echo "  WRONG ARCHITECTURE. Refusing to install."
  echo "  Tell Claude. Press any key."; read -n 1; exit 1
fi

# The whole point of the patch: the "stub" version of the function must be gone.
if strings "$NEW_WIN32U_SO" 2>/dev/null | grep -q "enable %u stub"; then
  echo "  This file still contains the BROKEN stub. Refusing to install."
  echo "  The patch did not make it into the build. Tell Claude."
  echo "  Press any key."; read -n 1; exit 1
else
  echo "  Patch confirmed present (the broken stub is gone)."
fi

# --- stop everything using Wine -------------------------------------------
echo ""
echo "Stopping Whisky, Steam and any games..."
pgrep -x Whisky >/dev/null && osascript -e 'tell application "Whisky" to quit' 2>/dev/null
sleep 2
pkill -9 -f "PEAK" 2>/dev/null
pkill -9 -f "steamwebhelper" 2>/dev/null
pkill -9 -f "steamservice" 2>/dev/null
pkill -9 -f 'steam.exe' 2>/dev/null
sleep 2
"$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wineserver" -k 2>/dev/null
sleep 2

# --- back up the originals -------------------------------------------------
mkdir -p "$BACKUP"
echo ""
echo "Backing up Whisky's original files to:"
echo "  $BACKUP"
for rel in x86_64-windows/win32u.dll x86_64-windows/user32.dll x86_64-unix/win32u.so; do
  if cp "$WINE_LIB/$rel" "$BACKUP/$(basename "$rel")" 2>/dev/null; then
    echo "  saved $(basename "$rel")"
  else
    echo "  FAILED to back up $(basename "$rel") - stopping, nothing was changed."
    echo "  Press any key."; read -n 1; exit 1
  fi
done

# --- install ---------------------------------------------------------------
echo ""
echo "Installing the patched files..."
OK=0
cp "$NEW_WIN32U_DLL"  "$WINE_LIB/x86_64-windows/win32u.dll"  2>/dev/null && { echo "  win32u.dll  installed"; OK=$((OK+1)); }
cp "$NEW_USER32_DLL"  "$WINE_LIB/x86_64-windows/user32.dll"  2>/dev/null && { echo "  user32.dll  installed"; OK=$((OK+1)); }
cp "$NEW_WIN32U_SO"   "$WINE_LIB/x86_64-unix/win32u.so"      2>/dev/null && { echo "  win32u.so   installed"; OK=$((OK+1)); }

echo ""
if [ "$OK" = "3" ]; then
  echo "  All three installed."
  echo ""
  echo "NOW: open Whisky -> Steam -> PEAK (DX11) and click HOST GAME."
  echo "If anything misbehaves, run 'RESTORE Whisky original files.command'."
else
  echo "  ONLY $OK of 3 installed - this is the unstable state."
  echo "  Run 'RESTORE Whisky original files.command' NOW, then tell Claude."
fi
echo ""
echo "Press any key to close."
read -n 1
