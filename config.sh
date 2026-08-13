#!/bin/bash
# Shared settings for all the scripts in this folder.
# Everything else reads from here, so this is the only file to edit.

# --- Wine ------------------------------------------------------------------
WINE_APP="/Applications/Wine Staging.app"
WINE="$WINE_APP/Contents/Resources/wine/bin/wine"
WINESERVER="$WINE_APP/Contents/Resources/wine/bin/wineserver"

# The "prefix" - a self-contained fake Windows C: drive.
export WINEPREFIX="$HOME/Games/wine-gaming"

# --- DXMT (DirectX 11 -> Apple Metal) --------------------------------------
# IMPORTANT: DXMT lives in its OWN folder and is switched on with
# WINEDLLPATH_PREPEND. Do NOT copy DXMT's DLLs over Wine's own files inside
# Wine Staging.app. Doing that corrupts the Wine install and makes Steam's
# interface render as a solid black window (learned the hard way).
# CORRECTED 2026-08-11: this used to say WINEDLLPATH_PREPEND, which DOES NOT
# EXIST in these Wine builds - searching both installed Wine trees for that
# text finds nothing. It was a no-op, so DXMT was never once loaded, and every
# "we tried DXMT" result was really plain Wine. The real variable is
# WINEDLLPATH, and DXMT's folder layout (i386-windows / x86_64-windows /
# x86_64-unix) is deliberately identical to Wine's own lib/wine/, so pointing
# it at the parent folder is exactly right.
DXMT_ROOT="$HOME/DXMT"
if [ -d "$DXMT_ROOT" ]; then
  export WINEDLLPATH="$DXMT_ROOT${WINEDLLPATH:+:$WINEDLLPATH}"
  # Prefer the built-in (DXMT) versions of these over Wine's own.
  export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
  export DXMT_LOG_LEVEL="${DXMT_LOG_LEVEL:-error}"
fi

# Quiet Wine's debug spam but keep real errors.
export WINEDEBUG="${WINEDEBUG:--all,err+all}"

# --- Steam -----------------------------------------------------------------
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
STEAMAPPS="$STEAM_DIR/steamapps"

# FPS overlay. Stored next to the prefix (not on the Desktop) so that
# "Windows Steam.app" can read it too - macOS privacy protection blocks
# unsigned apps from reading Desktop files.
HUD_STATE_FILE="$WINEPREFIX/.hud_enabled"
if [ -f "$HUD_STATE_FILE" ] && [ "$(cat "$HUD_STATE_FILE")" = "1" ]; then
  export MTL_HUD_ENABLED=1
fi

# --- helpers ---------------------------------------------------------------

wine_check() {
  if [ ! -x "$WINE" ]; then
    echo "ERROR: Wine not found at:"
    echo "  $WINE"
    echo ""
    echo "See README.txt for how to reinstall it."
    return 1
  fi
  return 0
}

# Start Steam if it isn't already up. Waits until it's actually ready.
ensure_steam() {
  if pgrep -f "steam.exe" >/dev/null 2>&1; then
    echo "  Steam is already running."
    return 0
  fi
  echo "  Starting Windows Steam (first start takes ~40 seconds)..."
  nohup "$WINE" "$STEAM_EXE" >/tmp/wine-steam.log 2>&1 &
  for i in $(seq 1 30); do
    sleep 3
    pgrep -f "steamwebhelper" >/dev/null 2>&1 && { echo "  Steam is ready."; return 0; }
  done
  echo "  Steam started but its UI is still loading - give it a moment."
  return 0
}
