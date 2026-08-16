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
ORIG="$HERE/whisky-original/win32u.so"

hdr() { echo ""; echo "=== $* ==="; }
ok()  { echo "  [ ok ] $*"; }
bad() { echo "  [ !! ] $*"; }
inf() { echo "         $*"; }

# Print the bottle paths recorded in one of Whisky's BottleVM.plist files.
# Paths are stored as file:// URLs, so they need URL-decoding for folders with
# spaces in them.
read_bottle_registry() {
  python3 - "$1" 2>/dev/null <<'PLIST_EOF'
import plistlib, sys, urllib.parse
try:
    d = plistlib.load(open(sys.argv[1], 'rb'))
except Exception:
    sys.exit(0)
for e in d.get('paths', []):
    u = e.get('relative', '') if isinstance(e, dict) else str(e)
    if u.startswith('file://'):
        print(urllib.parse.unquote(u[7:]).rstrip('/'))
PLIST_EOF
}

echo "==================================================="
echo "  Whisky mouse-fix doctor"
echo "  $(date '+%Y-%m-%d %H:%M')"
echo "==================================================="

# --- the Mac ----------------------------------------------------------------
hdr "Your Mac"
inf "macOS   : $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
inf "chip    : $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
# Which account, and whether it can use sudo. Both matter: Whisky keeps its
# bottles and its Wine engine SEPARATELY per macOS user, so running this in the
# wrong account gives a correct report about the wrong world.
if id -Gn 2>/dev/null | grep -qw admin; then
  inf "user    : $(whoami)  (administrator - can use sudo)"
else
  inf "user    : $(whoami)  (standard account - cannot use sudo)"
fi
ME=$(whoami)
OTHER_USERS=""
for u in /Users/*/; do
  n=$(basename "${u%/}")
  [ "$n" = "Shared" ] && continue
  [ "$n" = "Guest" ] && continue
  [ "$n" = "$ME" ] && continue
  OTHER_USERS="$OTHER_USERS $n"
done
[ -n "$OTHER_USERS" ] && inf "other accounts:$OTHER_USERS"
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
  FLAGS=$(ls -lO "$ENGINE" 2>/dev/null | awk '{print $5}')
  inf "size $SZ bytes, owned by $OWNER, flags: ${FLAGS:--}"
  # Permission denied has several independent causes on macOS and they look
  # identical. Name which one, because only the first is fixed by chown.
  if [ "$OWNER" != "$(whoami)" ]; then
    bad "owned by $OWNER, not you - installing will fail with Permission denied"
    inf "fix: sudo chown -R \"$(whoami)\" \"$HOME/Library/Application Support/com.franke.Whisky\""
    inf "     (do NOT run the installer itself with sudo - that is what creates"
    inf "      root-owned files in your home folder in the first place)"
  elif [ "$FLAGS" != "-" ] && [ -n "$FLAGS" ]; then
    bad "file is locked with flags: $FLAGS - you own it but still cannot write"
    inf "fix: chflags -R nouchg \"$HOME/Library/Application Support/com.franke.Whisky\""
  elif [ ! -w "$ENGINE" ]; then
    bad "you own it but it is read-only"
    inf "fix: chmod u+w \"$ENGINE\""
  fi
  [ -f "$ORIG" ] && ok "original backed up (uninstall is possible)" \
                 || inf "no backup yet - one is made on first install"
fi

# --- bottles ----------------------------------------------------------------
# Ask Whisky where its bottles are. They do not have to be in the default
# folder - Whisky supports putting them anywhere, external drives included - so
# scanning one directory reports "no bottles" on a machine that has one.
hdr "Bottles"
# Whisky's data lives under one of several roots depending on which build
# created it - the maintained fork, or the ARCHIVED original that
# `brew install --cask whisky` still installs - and either can be sandboxed
# (Containers/) or not (Application Support/). Checking only one is how a
# machine with a perfectly good bottle gets told it has none.
ROOTS=(
  "$HOME/Library/Containers/com.franke.Whisky"
  "$HOME/Library/Application Support/com.franke.Whisky"
  "$HOME/Library/Containers/com.isaacmarovitz.Whisky"
  "$HOME/Library/Application Support/com.isaacmarovitz.Whisky"
)
echo "  Locations checked:"
for r in "${ROOTS[@]}"; do
  if [ -d "$r" ]; then
    echo "    [found]   ${r/#$HOME/~}"
    # Show what is actually inside. Reporting only "found/absent" hid the fact
    # that a root existed but held something other than the expected Bottles
    # folder - which is exactly the case that stalled this diagnosis.
    for item in "$r"/*; do
      [ -e "$item" ] && echo "                 - $(basename "$item")"
    done
  else
    echo "    [absent]  ${r/#$HOME/~}"
  fi
done
echo ""

# Gather every candidate first, then dedupe - the registry and the folder scan
# usually name the same bottle.
SEEN=$(mktemp)
for r in "${ROOTS[@]}"; do
  [ -f "$r/BottleVM.plist" ] && read_bottle_registry "$r/BottleVM.plist" >> "$SEEN"
  if [ -d "$r/Bottles" ]; then
    for b in "$r/Bottles"/*/; do
      [ -d "${b}drive_c" ] && echo "${b%/}" >> "$SEEN"
    done
  fi
done

FOUND=0
while IFS= read -r b; do
  [ -n "$b" ] || continue
  if [ -d "$b/drive_c" ]; then
    FOUND=$((FOUND+1))
    name=$(plutil -extract info.name raw "$b/Metadata.plist" 2>/dev/null || echo "unnamed")
    steam=""; [ -f "$b/drive_c/Program Files (x86)/Steam/steam.exe" ] && steam="  [has Steam]"
    ok "\"$name\"$steam"; inf "$b"
  else
    bad "registered but missing from disk: $b"
    inf "(external drive unplugged, or the bottle was deleted)"
  fi
done < <(sort -u "$SEEN")
rm -f "$SEEN"

# Still nothing? Stop guessing at paths and search the disk properly.
# A bottle does NOT have to be in the home folder - Whisky supports external and
# network volumes - so searching only ~ can come back empty on a machine that is
# happily running games.
if [ "$FOUND" = 0 ]; then
  bad "no bottle in any known location - searching the disk..."
  inf "home folder..."
  HITS=$(find "$HOME" -maxdepth 8 -name "drive_c" -type d 2>/dev/null | head -10)

  if [ -z "$HITS" ] && [ -d /Volumes ]; then
    inf "attached volumes..."
    for v in /Volumes/*; do
      [ -d "$v" ] || continue
      inf "  checking $v"
      more=$(find "$v" -maxdepth 8 -name "drive_c" -type d 2>/dev/null | head -5)
      [ -n "$more" ] && HITS="$HITS$more"$'\n'
    done
  fi
  if [ -z "$HITS" ]; then
    inf "shared folders..."
    HITS=$(find /Users/Shared -maxdepth 8 -name "drive_c" -type d 2>/dev/null | head -5)
  fi

  if [ -n "$HITS" ]; then
    echo ""
    ok "found a Wine prefix the scripts didn't know about:"
    echo "$HITS" | while IFS= read -r d; do [ -n "$d" ] && inf "$(dirname "$d")"; done
    echo ""
    inf "point the scripts at it:"
    inf "  echo '$(dirname "$(echo "$HITS" | head -1)")' > \"$REPO/Playing/bottle.conf\""
  else
    echo ""
    # THE most likely explanation, and the one that costs the most time:
    # Whisky's data is per-account. A report saying "no bottle" is completely
    # correct while being about the wrong user entirely.
    OTHER_WHISKY=""
    for u in /Users/*/; do
      n=$(basename "${u%/}")
      [ "$n" = "Shared" ] && continue
      [ "$n" = "Guest" ] && continue
      [ "$n" = "$(whoami)" ] && continue
      if [ -d "${u}Library/Containers/com.franke.Whisky" ] \
      || [ -d "${u}Library/Application Support/com.franke.Whisky" ]; then
        OTHER_WHISKY="$OTHER_WHISKY $n"
      fi
    done

    if [ -n "$OTHER_WHISKY" ]; then
      bad "NO BOTTLE IN THIS ACCOUNT - but Whisky is set up in another one:$OTHER_WHISKY"
      inf ""
      inf "You are logged in as \"$(whoami)\". Whisky keeps its bottles AND its"
      inf "Wine engine separately for every macOS user, so work done here has no"
      inf "effect on the account you actually play in."
      inf ""
      inf "Log out, log into that account, and run the install from there:"
      inf "  git clone https://github.com/zeno-blade-creator/whisky-unity-mouse-fix.git ~/whisky-mouse-fix"
      inf "  cd ~/whisky-mouse-fix/Software/wine-patch && ./install.sh"
    else
      bad "no Wine prefix exists anywhere this script can see."
      inf "Either no bottle has been created yet, or it is on a drive or network"
      inf "share that isn't mounted, or it belongs to another macOS account whose"
      inf "files this account cannot read."
      inf ""
      inf "Open Whisky and look at its bottle list:"
      inf "  - if it shows a bottle, click it, then 'Open C: Drive', then Cmd+I"
      inf "    on the folder - the 'Where:' line is the path. Check the username"
      inf "    in that path matches \"$(whoami)\"."
      inf "  - if the list is empty, create a bottle and install Steam into it"
    fi
  fi
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
