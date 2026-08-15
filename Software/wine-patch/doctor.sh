#!/bin/bash
# Checks everything and prints one report. Changes nothing.
#
#     ./doctor.sh
#
# Run this when something isn't working, and send someone the whole output.
# It answers, in order, every question that has actually come up:
#
#   - Is the mouse fix installed, or still the stock engine?
#   - Is Whisky where we expect, and which version?
#   - Is the graphics stack a consistent DXMT set, or the broken mixed one?
#   - Are the DLL overrides actually in the bottle registry?
#   - Do you own your own files, or did something get installed as root?
#   - Did a game launcher ever get created, and where?
#   - Is there a build sitting there ready to install?
#
# Everything is read-only. It is safe to run at any time.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WLIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries"
ENGINE="$WLIB/Wine/lib/wine/x86_64-unix/win32u.so"
BOTTLES="$HOME/Library/Containers/com.franke.Whisky/Bottles"
ORIG="$HERE/whisky-original/win32u.so"

hdr() { echo ""; echo "=== $* ==="; }
ok()  { echo "  [ ok ] $*"; }
bad() { echo "  [ !! ] $*"; }
inf() { echo "         $*"; }

echo "==================================================="
echo "  Whisky mouse-fix doctor"
echo "  $(date '+%Y-%m-%d %H:%M')"
echo "==================================================="

# --- the Mac ----------------------------------------------------------------
hdr "Your Mac"
inf "macOS   : $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
inf "chip    : $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
inf "user    : $(whoami)"
# Compare numerically rather than matching version prefixes. Apple switched to
# year-based numbering after Sequoia (15 -> 26), so a hardcoded list of
# acceptable major versions goes stale and starts failing correct machines.
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "${MAJOR:-0}" -ge 15 ] 2>/dev/null; then
  ok "macOS version supported by Whisky"
else
  bad "Whisky needs macOS Sequoia 15.0 or later - this is $(sw_vers -productVersion)"
fi

# --- Whisky -----------------------------------------------------------------
hdr "Whisky"
APP=""
for p in /Applications/Whisky.app "$HOME/Applications/Whisky.app"; do
  [ -d "$p" ] && APP="$p"
done
if [ -n "$APP" ]; then
  ok "installed: $APP"
  inf "version : $(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null)"
else
  bad "Whisky.app not found. Install: brew install --cask frankea/whisky/whisky"
fi
if [ -d "$WLIB/Wine" ]; then
  ok "Wine engine present"
else
  bad "Whisky's Wine libraries are missing - open Whisky once to download them"
fi

# --- THE MAIN QUESTION ------------------------------------------------------
hdr "Is the mouse fix installed?"
if [ ! -f "$ENGINE" ]; then
  bad "engine file not found: $ENGINE"
else
  SZ=$(stat -f %z "$ENGINE")
  OWNER=$(stat -f '%Su' "$ENGINE")
  if strings -a "$ENGINE" 2>/dev/null | grep -q "enable %u stub!"; then
    bad "NOT INSTALLED - this is the stock engine. Clicks will not work."
    inf "fix: cd \"$HERE\" && ./install-pointer-fix.sh install"
  else
    ok "INSTALLED - the pointer API is implemented. Clicks should work."
  fi
  inf "size $SZ bytes, owned by $OWNER"
  if [ "$OWNER" != "$(whoami)" ]; then
    bad "owned by $OWNER, not you - installing will fail with Permission denied"
    inf "fix: sudo chown -R \"$(whoami)\" \"$HOME/Library/Application Support/com.franke.Whisky\""
  elif [ ! -w "$ENGINE" ]; then
    bad "you own it but cannot write to it"
    inf "fix: chmod u+w \"$ENGINE\""
  fi
  [ -f "$ORIG" ] && ok "original backed up (uninstall is possible)" \
                 || inf "no backup yet - one is made on first install"
fi

# --- bottles ----------------------------------------------------------------
hdr "Bottles"
if [ ! -d "$BOTTLES" ]; then
  bad "no bottles folder - create a bottle in Whisky first"
else
  n=0
  for b in "$BOTTLES"/*/; do
    [ -d "${b}drive_c" ] || continue
    n=$((n+1))
    name=$(plutil -extract info.name raw "${b}Metadata.plist" 2>/dev/null || echo "unnamed")
    steam=""
    [ -f "${b}drive_c/Program Files (x86)/Steam/steam.exe" ] && steam="  [has Steam]"
    inf "$(basename "${b%/}")  \"$name\"$steam"
  done
  [ "$n" = 0 ] && bad "no bottles found" || ok "$n bottle(s) found"
fi

# --- graphics ---------------------------------------------------------------
hdr "Graphics stack (DXMT)"
B=""
if [ -f "$REPO/Playing/config.sh" ]; then
  # shellcheck disable=SC1091
  B=$(cd "$REPO/Playing" && bash -c 'source ./config.sh >/dev/null 2>&1; echo "$WINEPREFIX"' 2>/dev/null)
fi
if [ -z "$B" ] || [ ! -d "$B" ]; then
  bad "could not work out which bottle to check"
else
  inf "checking: $(basename "$B")"
  mixed=0
  for f in d3d11.dll d3d10core.dll dxgi.dll winemetal.dll; do
    have="$B/drive_c/windows/system32/$f"
    want="$WLIB/DXMT/x64/$f"
    if [ ! -f "$have" ]; then
      bad "$f missing"; mixed=1
    elif [ "$(md5 -q "$have" 2>/dev/null)" = "$(md5 -q "$want" 2>/dev/null)" ]; then
      ok "$f is DXMT"
    else
      alt="$WLIB/DXVK/x64/$f"
      if [ -f "$alt" ] && [ "$(md5 -q "$have")" = "$(md5 -q "$alt")" ]; then
        bad "$f is DXVK, not DXMT  <- mixed stack, the game will crash at startup"
      else
        bad "$f is neither DXMT nor DXVK"
      fi
      mixed=1
    fi
  done
  [ "$mixed" = 1 ] && inf "fix: run Playing/\"FIX graphics stack.command\""

  hdr "DLL overrides in the bottle registry"
  if [ -f "$B/user.reg" ]; then
    for k in d3d11 d3d10core dxgi winemetal; do
      v=$(grep -m1 "^\"$k\"=" "$B/user.reg" 2>/dev/null | cut -d'"' -f4)
      want="native"; [ "$k" = "winemetal" ] && want="builtin"
      if [ "$v" = "$want" ]; then ok "$k = $v"
      else bad "$k = ${v:-<not set>}   (should be $want)"; fi
    done
  else
    bad "no user.reg in the bottle"
  fi
fi

# --- the download itself -----------------------------------------------------
hdr "Your copy of this project"
inf "location: $REPO"
OWNER=$(stat -f '%Su' "$REPO" 2>/dev/null)
if [ "$OWNER" != "$(whoami)" ]; then
  bad "owned by $OWNER, not you - scripts will fail to write files"
  inf "fix: sudo chown -R \"$(whoami)\" \"$REPO\""
elif [ ! -w "$REPO/Playing" ]; then
  bad "Playing folder is not writable - Add a game cannot create a launcher"
  inf "fix: chmod -R u+w \"$REPO\""
else
  ok "you own it and can write to it"
fi

hdr "Game launchers"
found=0
for f in "$REPO/Playing/Play "*.command; do
  [ -f "$f" ] || continue
  found=$((found+1)); ok "$(basename "$f")"
done
if [ "$found" = 0 ]; then
  bad "none yet - run Playing/\"Add a game.command\" to make one"
  inf "(any elsewhere on this Mac?)"
  find "$HOME" -name "Play *.command" -not -path "*/.git/*" 2>/dev/null | head -5 | sed 's/^/         /'
fi

hdr "Build"
BUILT="$HERE/crossover-src/sources/wine/dlls/win32u/win32u.so"
if [ -f "$BUILT" ]; then
  ok "a compiled engine is ready: $(stat -f %z "$BUILT") bytes"
  inf "install it with: ./install-pointer-fix.sh install   (no rebuild needed)"
else
  inf "no build present - install.sh will download and build one"
fi
[ -f "$HERE/crossover-sources-26.3.0.tar.gz" ] \
  && ok "source tarball downloaded ($(du -h "$HERE/crossover-sources-26.3.0.tar.gz" | cut -f1))" \
  || inf "source not downloaded yet"

echo ""
echo "==================================================="
echo "  End of report - send this whole output"
echo "==================================================="
echo ""
