#!/bin/bash
# Shared settings for the scripts in this folder. Everything sources this, so
# it is the only file to edit when something moves.
#
# REWRITTEN 2026-08-13 for Whisky. The previous version pointed at
# "Wine Staging.app" and a ~/Games/wine-gaming prefix, neither of which exists
# any more, so every script that sourced it failed on the first line.

# --- Wine engine ------------------------------------------------------------
# Whisky's bundled Wine. This is NOT vanilla Wine - it is CrossOver's Wine,
# confirmed by comparing the two binaries (identical import lists, one export
# apart). That matters: patches written for vanilla Wine are not drop-in here.
WHISKY_LIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries"
WINE="$WHISKY_LIB/Wine/bin/wine"
WINESERVER="$WHISKY_LIB/Wine/bin/wineserver"

# The bottle - a self-contained fake Windows C: drive, holding Steam and games.
export WINEPREFIX="$HOME/Library/Containers/com.franke.Whisky/Bottles/2E15BCAB-7F6A-4116-9BBF-2A78C47970B1"

# --- Direct3D translation ---------------------------------------------------
# DXMT translates Direct3D 11 -> Apple Metal. Without it there is no working
# D3D11 on macOS, Steam's Chromium interface never paints, and you get the
# infamous black window.
#
# Wine prefers its OWN d3d11 unless told otherwise. Whisky sets this variable
# only when WHISKY launches something, so any script that calls wine directly
# has to set it too - otherwise Wine silently falls back to its builtin
# d3d11 -> wined3d -> OpenGL path, which cannot create a device on a Mac.
#
# winemetal is deliberately "b" (builtin), NOT native: its .dll is a thin shim
# that must pair with winemetal.so (31 MB) compiled INTO Wine, and Wine only
# pairs the two for builtin DLLs. Forcing it native breaks dxgi, and Steam with
# it.
#
# HISTORICAL NOTE, kept because it cost days: an earlier version of this file
# used WINEDLLPATH_PREPEND to "enable" DXMT. That variable exists in NO Wine
# build anywhere - it was a silent no-op, so DXMT was never once loaded and
# every "we tried DXMT" result was really plain Wine. A popular project still
# recommends it. Verify a setting is read before trusting any result from it.
export WINEDLLOVERRIDES="d3d11,d3d10core,dxgi=n;winemetal=b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

# Quiet Wine's debug spam but keep real errors.
export WINEDEBUG="${WINEDEBUG:--all,err+all}"

# --- Steam ------------------------------------------------------------------
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
STEAMAPPS="$STEAM_DIR/steamapps"

# --- helpers ----------------------------------------------------------------

wine_check() {
  if [ ! -x "$WINE" ]; then
    echo "ERROR: Whisky's Wine not found at:"
    echo "  $WINE"
    echo ""
    echo "Is Whisky installed? Get it from https://github.com/frankea/Whisky"
    return 1
  fi
  if [ ! -d "$WINEPREFIX" ]; then
    echo "ERROR: the Whisky bottle is missing:"
    echo "  $WINEPREFIX"
    return 1
  fi
  return 0
}

# Make sure the Direct3D layer is a consistent DXMT set, and repair it if not.
#
# Whisky switches graphics backends by COPYING DLLs into the bottle, but its
# DXVK package contains only 2 files where DXMT has 6, and nothing removes the
# old ones. So launching a game from Whisky can leave DXVK's d3d11 sitting on
# DXMT's dxgi - two unrelated implementations - which fails device creation with
# 0x80004005 and crashes the game at startup looking like something else
# entirely. Repair rather than refuse, or one launch from Whisky leaves the
# bottle unplayable.
ensure_dxmt() {
  local sys32="$WINEPREFIX/drive_c/windows/system32"
  local syswow="$WINEPREFIX/drive_c/windows/syswow64"
  local bad="" f
  [ -d "$WHISKY_LIB/DXMT/x64" ] || { echo "  DXMT library missing - cannot verify graphics"; return 1; }

  for f in d3d11.dll d3d10core.dll dxgi.dll winemetal.dll; do
    if [ ! -f "$sys32/$f" ] || \
       [ "$(md5 -q "$sys32/$f" 2>/dev/null)" != "$(md5 -q "$WHISKY_LIB/DXMT/x64/$f" 2>/dev/null)" ]; then
      bad="$bad $f"
    fi
  done

  if [ -n "$bad" ]; then
    echo "  Direct3D layer was overwritten - repairing:$bad"
    for f in d3d11.dll d3d10core.dll dxgi.dll winemetal.dll; do
      cp -f "$WHISKY_LIB/DXMT/x64/$f" "$sys32/$f"  2>/dev/null
      cp -f "$WHISKY_LIB/DXMT/x32/$f" "$syswow/$f" 2>/dev/null
    done
    echo "  repaired - DXMT restored"
  else
    echo "  Graphics layer: DXMT verified."
  fi
  return 0
}

# Start Steam if it isn't already up. Waits until it's actually ready.
#
# NOTE the -i on pgrep. The process is "Steam.exe" with a capital S, and
# pgrep is case-sensitive - a previous version searched for "steam.exe", never
# matched, and happily started a second copy every time.
ensure_steam() {
  if pgrep -if "steam.exe" >/dev/null 2>&1; then
    echo "  Steam is already running."
    return 0
  fi
  echo "  Starting Windows Steam (first start takes ~40 seconds)..."
  nohup "$WINE" "$STEAM_EXE" >/tmp/wine-steam.log 2>&1 &
  for i in $(seq 1 30); do
    sleep 3
    pgrep -if "steamwebhelper" >/dev/null 2>&1 && { echo "  Steam is ready."; return 0; }
  done
  echo "  Steam started but its UI is still loading - give it a moment."
  return 0
}
