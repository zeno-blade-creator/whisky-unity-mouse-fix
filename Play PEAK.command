#!/bin/bash
# Launches PEAK, and repairs its display settings first so it can never get
# stuck in an unlaunchable state.
#
# THE PROBLEM THIS SOLVES
# -----------------------
# PEAK remembers the screen resolution you last used. On a Retina Mac that
# remembered value can be something like 1470x891 - which is a size macOS
# *pretends* the screen is for menus and text, not a real mode the display can
# actually switch to.
#
# Wine checks requested resolutions against the REAL modes the monitor
# supports. When it can't find a match it gives up:
#
#     "Couldn't switch to requested monitor resolution"
#     "DX11 could not switch resolution (1470x891 fs=1)"
#
# and the game never starts. Worse, the bad value stays saved, so every future
# launch fails the same way. That is how PEAK became unlaunchable.
#
# HOW THIS FIXES IT PERMANENTLY
# ------------------------------
# Before each launch it simply DELETES the remembered resolution. It does not
# write a new one.
#
# That matters: Unity's "borderless fullscreen" mode is defined as "use the
# display's native resolution". With nothing remembered, the game asks for the
# screen's real size - which always exists, on any monitor - so the lookup that
# used to fail cannot fail.
#
# Because there is no number written anywhere, this works the same on the
# built-in screen, on the DELL ultrawide, and on any monitor you plug in later.
#
# WHAT IT LEAVES ALONE
#   Your fullscreen/windowed preference is preserved. The only exception is
#   "exclusive fullscreen", which is the one mode that demands a real display
#   mode change and can therefore fail - that gets switched to borderless
#   fullscreen, which looks identical and cannot fail.
#
#   Volume, keybinds, graphics quality and everything else are untouched.
#
# SO: change resolution in-game freely, toggle fullscreen, move to the other
# monitor, quit however you like. The next launch always starts clean.

set -u
BOTTLE="$HOME/Library/Containers/com.franke.Whisky/Bottles/2E15BCAB-7F6A-4116-9BBF-2A78C47970B1"
WINE="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin"
export WINEPREFIX="$BOTTLE"
export WINEDEBUG=-all,err+all
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
PEAK_APPID=3527290

# Wine prefers its OWN d3d11.dll over the DXMT one sitting in system32 unless
# it is told otherwise. Whisky sets this variable when WHISKY launches a game;
# this script calls wine directly, so it has to set it itself. Without it the
# game silently falls back to Wine's builtin d3d11 -> wined3d -> OpenGL, which
# cannot create a graphics device on a Mac, and the game dies at startup
# looking like a completely different bug. ("n" = native = use system32's copy.)
#
# winemetal is deliberately "b" (builtin), NOT native, and getting this wrong
# breaks everything including Steam's UI. winemetal is only half a DLL: the
# .dll is a thin PE shim that must pair with winemetal.so (31 MB) built INTO
# Wine itself. Wine only pairs the two for builtin DLLs. Force it native and
# the shim loads with no engine behind it, so dxgi.dll - which imports it -
# fails outright:
#     err:module:import_dll Library winemetal.dll ... not found
# d3d11 / d3d10core / dxgi have no .so counterpart, so native is right for them.
export WINEDLLOVERRIDES="d3d11,d3d10core,dxgi=n;winemetal=b"
LIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries"
PLAYER_LOG="$BOTTLE/drive_c/users/$USER/AppData/LocalLow/LandCrab/PEAK/Player.log"

echo "==================================================="
echo "  Play PEAK"
echo "==================================================="
echo ""

if [ ! -d "$BOTTLE" ]; then
  echo "ERROR: the Whisky bottle is missing:"; echo "  $BOTTLE"
  echo "Press any key."; read -n 1; exit 1
fi

# --- preflight: is the graphics translation layer actually intact? ----------
# Whisky switches between DXMT and DXVK by copying DLLs into system32, but the
# two packages contain DIFFERENT file lists, and nothing deletes the old ones.
# Switching backends therefore leaves a MIXTURE - DXVK's d3d11 on DXMT's dxgi -
# which cannot create a device and crashes the game at startup with
# "d3d11: failed to create device and context (80004005)".
#
# That is what silently broke on Aug 12. It is invisible unless you check, so
# this checks, every launch, and refuses to start rather than hand you a
# mystery crash.
check_stack() {
  bad=""
  for f in d3d11.dll d3d10core.dll dxgi.dll winemetal.dll; do
    have="$BOTTLE/drive_c/windows/system32/$f"
    want="$LIB/DXMT/x64/$f"
    if [ ! -f "$have" ] || [ ! -f "$want" ] || \
       [ "$(md5 -q "$have" 2>/dev/null)" != "$(md5 -q "$want" 2>/dev/null)" ]; then
      bad="$bad $f"
    fi
  done
}

check_stack
if [ -n "$bad" ]; then
  echo "The Direct3D layer was overwritten - repairing:$bad"
  # This happens every time the game is started FROM WHISKY rather than from
  # this script: Whisky re-applies its configured backend on launch, and its
  # DXVK package contains only d3d11 + d3d10core, so it overwrites two of
  # DXMT's four files and leaves the other two. Repair rather than refuse,
  # because otherwise one launch from Whisky leaves the game unplayable.
  for f in d3d11.dll d3d10core.dll dxgi.dll winemetal.dll; do
    cp -f "$LIB/DXMT/x64/$f" "$BOTTLE/drive_c/windows/system32/$f" 2>/dev/null
    cp -f "$LIB/DXMT/x32/$f" "$BOTTLE/drive_c/windows/syswow64/$f"  2>/dev/null
  done

  check_stack
  if [ -n "$bad" ]; then
    echo ""
    echo "STOP - repair failed for:$bad"
    echo "Run 'FIX graphics stack.command' and read what it reports."
    echo ""
    echo "Press any key."; read -n 1; exit 1
  fi
  echo "  repaired - all four DLLs are DXMT again"
else
  echo "Graphics layer: DXMT, all four DLLs verified."
fi

# Stop it happening again. Whisky overwrites the DLLs because the bottle is
# still configured to want DXVK; setting the backend to DXMT makes Whisky
# re-apply the RIGHT thing instead of the wrong one.
META="$BOTTLE/Metadata.plist"
if [ -f "$META" ] && ! plutil -p "$META" 2>/dev/null | grep -q '"backend" => "dxmt"'; then
  pgrep -x Whisky >/dev/null || {
    plutil -replace graphicsConfig.backend -string "dxmt" "$META" 2>/dev/null
    plutil -replace launcherConfig.autoEnableDXVK -bool false "$META" 2>/dev/null
    echo "  set Whisky's own backend to DXMT so it stops re-applying DXVK"
  }
fi

# --- stop anything left over ------------------------------------------------
echo "Clearing anything still running..."
pgrep -x Whisky >/dev/null && osascript -e 'tell application "Whisky" to quit' 2>/dev/null
sleep 2
pkill -9 -if "PEAK"              2>/dev/null
pkill -9 -if "UnityCrashHandler" 2>/dev/null
pkill -9 -if "steamwebhelper"    2>/dev/null
pkill -9 -if "steamerrorreporter" 2>/dev/null
pkill -9 -if "steamservice"      2>/dev/null
pkill -9 -if "steam.exe"         2>/dev/null
pkill -9 -if "conhost.exe"       2>/dev/null
pkill -9 -x  winedbg             2>/dev/null
sleep 2
"$WINE/wineserver" -k 2>/dev/null
sleep 2

# --- repair the remembered display settings ---------------------------------
cp "$BOTTLE/user.reg" "$BOTTLE/user.reg.bak-play-$(date +%Y%m%d-%H%M%S)" 2>/dev/null

# Unity appends a hash to each setting name, and it differs per game, so the
# exact names are discovered from the registry rather than hardcoded.
RES_KEYS=$(grep -oE '"Screenmanager Resolution (Width|Height)[^"]*"' "$BOTTLE/user.reg" 2>/dev/null | tr -d '"' | sort -u)

if [ -n "$RES_KEYS" ]; then
  echo "Clearing PEAK's remembered resolution so it uses your screen's real size:"
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    "$WINE/wine" reg delete 'HKCU\Software\LandCrab\PEAK' /v "$k" /f >/dev/null 2>&1 \
      && echo "  cleared: $k"
  done <<< "$RES_KEYS"
else
  echo "No remembered resolution found - nothing to clear (this is fine)."
fi

# Only "exclusive fullscreen" (value 0) is dangerous. Anything else is kept.
MODE_KEY=$(grep -oE '"Screenmanager Fullscreen mode_h[0-9]+"' "$BOTTLE/user.reg" 2>/dev/null | tr -d '"' | head -1)
if [ -n "$MODE_KEY" ]; then
  MODE_VAL=$(grep -oE "\"$MODE_KEY\"=dword:[0-9a-f]+" "$BOTTLE/user.reg" 2>/dev/null | grep -oE '[0-9a-f]+$')
  if [ "$MODE_VAL" = "00000000" ]; then
    "$WINE/wine" reg add 'HKCU\Software\LandCrab\PEAK' /v "$MODE_KEY" /t REG_DWORD /d 1 /f >/dev/null 2>&1 \
      && echo "  switched exclusive fullscreen -> borderless fullscreen (cannot fail)"
  else
    echo "  fullscreen preference kept as-is"
  fi
fi

sleep 1
"$WINE/wineserver" -k 2>/dev/null
sleep 2

# --- launch -----------------------------------------------------------------
echo ""
echo "Starting Steam and launching PEAK..."
echo "(Steam takes a moment to start before the game appears.)"
echo ""
"$WINE/wine" "$STEAM_EXE" -applaunch "$PEAK_APPID" >/tmp/peak-launch.log 2>&1

echo ""
echo "PEAK/Steam exited."
echo ""

# --- report what the game itself said ---------------------------------------
# Unity writes its own log. Reading it is the difference between "it didn't
# work" and knowing WHY, so don't make anyone go hunting for it.
if [ -f "$PLAYER_LOG" ]; then
  echo "--- what PEAK reported about graphics ---"
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
  echo "-----------------------------------------"
  echo ""
fi

echo "If anything went wrong, run 'STOP everything.command' and try again."
echo "Press any key to close."
read -n 1
