#!/bin/bash
# Emergency stop. Kills Steam, any running game, and Wine itself.
#
# Use this when a window won't close, something keeps reopening, or things
# generally get stuck. It cannot damage anything - Wine is just programs, and
# your games and logins are stored on disk, not in these processes.
#
# WHY THINGS REOPEN: Steam installs a background Windows "service"
# (steamservice.exe) inside Wine that restarts Steam. Closing the Steam window
# does not stop it. This script kills the service too, which is the part that
# makes it actually stay closed.

echo "==================================================="
echo "  Stopping everything"
echo "==================================================="
echo ""

# Whisky is the setup that actually works now, so stop its engine too. The old
# standalone Wine is kept in the list only for leftovers from earlier attempts.
WINESERVER="/Applications/Wine Staging.app/Contents/Resources/wine/bin/wineserver"
WHISKY_WINESERVER="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wineserver"

echo "  Stopping games and Steam..."
pkill -9 -if "steamwebhelper" 2>/dev/null
pkill -9 -if "steamservice"   2>/dev/null
pkill -9 -if "steamerrorreporter" 2>/dev/null
pkill -9 -if "steam.exe"      2>/dev/null
pkill -9 -if "PEAK"           2>/dev/null
sleep 2

# --- winedbg: the REAL memory eater ----------------------------------------
# winedbg is Wine's crash debugger. Wine used to launch one automatically every
# time a Windows program crashed - and each one then hung around forever
# instead of exiting.
#
# On 2026-08-12 there were 1,325 of them. Killing them dropped swap from
# 15.0 GB to 2.1 GB and freed all the memory on the machine. Each crash also
# dragged a conhost.exe along with it, which is where those came from.
#
# The crash handler has since been removed from the bottle entirely (the
# AeDebug "Debugger" value was deleted), so crashes now end quietly instead of
# spawning anything. Setting Auto=0 alone was NOT enough - in Wine that means
# "ask the user first", which produced an endless run of "Exception raised"
# dialogs where closing one opened another.
#
# So this should stay at zero. If it doesn't, something is crashing repeatedly
# and the count below will say so.
DBGS=$(pgrep -x winedbg 2>/dev/null | wc -l | tr -d ' ')
if [ "$DBGS" != "0" ]; then
  echo "  Found $DBGS stuck crash-debuggers (winedbg) - removing..."
  pkill -9 -x winedbg 2>/dev/null
  [ "$DBGS" -gt 20 ] && echo "    NOTE: $DBGS crashes. Something is crash-looping."
  sleep 1
fi

# --- conhost.exe: dragged along by each crash -------------------------------
# conhost.exe is Windows' "console host". Normally there are one or two. But if
# a game crashes and something keeps restarting it, each attempt leaves one
# behind, orphaned, forever.
#
# On 2026-08-12 this had reached 976 of them - about 2.5 new ones every second -
# and had pushed the Mac to 20.6 GB of swap with 0.1 GB of memory left. Killing
# them freed 7 GB instantly.
#
# This script used to miss them completely, which is why they piled up.
CONHOSTS=$(pgrep -f "conhost.exe" 2>/dev/null | wc -l | tr -d ' ')
if [ "$CONHOSTS" != "0" ]; then
  echo "  Found $CONHOSTS leftover console processes (conhost.exe) - removing..."
  pkill -9 -if "conhost.exe" 2>/dev/null
  [ "$CONHOSTS" -gt 20 ] && echo "    NOTE: that many means something was crash-looping."
  sleep 1
fi

# Wine's own background services. Killing wineserver should take these with it,
# but orphans survive, so they are named explicitly.
for svc in "services.exe" "rpcss.exe" "plugplay.exe" "svchost.exe" "winedevice.exe"; do
  pkill -9 -if "$svc" 2>/dev/null
done
sleep 1

echo "  Stopping Wine..."
[ -x "$WINESERVER" ] && "$WINESERVER" -k 2>/dev/null
[ -x "$WHISKY_WINESERVER" ] && "$WHISKY_WINESERVER" -k 2>/dev/null
sleep 2
pkill -9 -f "winedevice" 2>/dev/null
pkill -9 -f "wineserver" 2>/dev/null
pkill -9 -f "wine64-preloader" 2>/dev/null
sleep 2

# --- explorer.exe: the one this script used to miss -------------------------
# explorer.exe is Wine's desktop manager - it owns the desktop that every
# window gets attached to. Killing wineserver does NOT kill it; it just gets
# orphaned and keeps running. Before this was added, 18 dead explorer.exe
# processes had built up over two days of testing, all still holding the
# wine-gaming prefix. That is a prime suspect for windows that open, respond
# to the mouse, and paint nothing.
#
# CrossOver runs its own explorer.exe and MUST NOT be touched - CrossOver is
# the setup that currently works. So each one is checked for whether it
# belongs to CrossOver, and skipped if it does.
echo "  Stopping leftover Wine desktops (explorer.exe)..."
KILLED=0
SKIPPED=0
for p in $(pgrep -f "explorer.exe" 2>/dev/null); do
  if lsof -p "$p" 2>/dev/null | grep -qi "CrossOver.app"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  kill -9 "$p" 2>/dev/null && KILLED=$((KILLED + 1))
done
sleep 1
echo "    removed $KILLED, left $SKIPPED CrossOver one(s) alone"

echo ""
# NOTE the -i. Without it this missed "Steam.exe" (capital S) and always
# reported "1 process still running" no matter how many times you ran it.
LEFT=$(pgrep -if "steam.exe|winedevice|wineserver|steamservice" 2>/dev/null | wc -l | tr -d ' ')
STALE=0
for p in $(pgrep -f "explorer.exe" 2>/dev/null); do
  lsof -p "$p" 2>/dev/null | grep -qi "CrossOver.app" || STALE=$((STALE + 1))
done
[ "$STALE" != "0" ] && echo "  WARNING: $STALE Wine desktop(s) still running - run this again."
if [ "$LEFT" = "0" ]; then
  echo "  Everything stopped."
else
  echo "  $LEFT process(es) still running. Run this once more."
fi

echo ""
echo "Press any key to close."
read -n 1
