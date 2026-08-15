#!/bin/bash
# Repairs the bottle's Direct3D translation layer, which is what actually
# broke on Aug 12 - NOT the mouse patch, and NOT the compiler.
#
#
# WHAT WENT WRONG
# ---------------
# A Windows game asks the system for a "D3D11 device". On a real PC that talks
# to the GPU driver. On a Mac there is no such thing, so a *translation layer*
# has to stand in and re-implement Direct3D on top of something Apple does
# support. There are two free ones:
#
#   DXMT - translates Direct3D -> Metal   (Apple's native graphics API)
#   DXVK - translates Direct3D -> Vulkan  (needs MoltenVK, another translator)
#
# Whisky ships both and lets you pick. It switches between them by COPYING
# DLL files into the bottle's windows/system32. That is where the trap is:
#
#   the DXMT package contains  d3d11, d3d10core, dxgi, winemetal (+2 NVIDIA shims)
#   the DXVK package contains  d3d11, d3d10core                    <-- only two
#
# So switching DXMT -> DXVK overwrites two of DXMT's files and LEAVES THE
# OTHER TWO IN PLACE. The bottle ends up with DXVK's d3d11.dll sitting on top
# of DXMT's dxgi.dll. Those are two different, unrelated implementations. When
# the game asks DXVK's d3d11 to create a device, d3d11 asks dxgi for the
# graphics adapter, doesn't recognise what DXMT hands back, and gives up with:
#
#     d3d11: failed to create device and context (80004005)
#     Failed to initialize graphics.
#
# 80004005 is just Windows for "E_FAIL / something went wrong". Unity then
# prints "GfxDevice: creating device client" for each retry and crashes. That
# GfxDevice line is Unity narrating a retry, not the thing that failed - which
# is why chasing it led nowhere.
#
# The switch is not transactional: nothing removes the previous backend's
# files. Verified on this machine - both system32 and syswow64 were left in
# the mixed state.
#
#
# THE SECOND HALF OF THE PROBLEM
# ------------------------------
# Copying the DLLs in is not enough. Wine ships its OWN d3d11.dll, and by
# default it prefers its own ("builtin") over anything sitting in system32
# ("native"). To use DXMT you must explicitly tell Wine "prefer native for
# these four".
#
# Whisky does that by setting the WINEDLLOVERRIDES environment variable when
# IT launches something. It does not write the setting into the bottle. So
# anything launched OUTSIDE Whisky - like the generated 'Play <game>.command', which calls
# wine directly - never gets the override, and silently falls back to Wine's
# builtin d3d11 -> wined3d -> OpenGL. On a Mac that path cannot create a
# device either. Proof, from the crash log's module list:
#
#     d3d11.dll  ... size: 454656      <- Wine's builtin. DXMT's is 5,350,886.
#     wined3d.dll ... size: 3178496    <- the OpenGL fallback, loaded
#
# This script fixes both halves, and writes the override into the bottle's
# registry so it survives no matter how the game is started.
#
#
# SAFE TO RUN ANY TIME. It backs up first, and it re-checks its own work at
# the end. If it cannot prove the fix landed it says VOID, not "done".

set -u

# The bottle is discovered, not hardcoded - see find_bottle() in config.sh.
# Hardcoding it would mean these scripts only ever worked on one machine.
cd "$(dirname "$0")" || exit 1
source ./config.sh

BOTTLE="${WINEPREFIX:-}"
LIB="$WHISKY_LIB"
SYS32="$BOTTLE/drive_c/windows/system32"
SYSWOW="$BOTTLE/drive_c/windows/syswow64"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$(pwd)/graphics-backup-$STAMP"

# The four files that make up a working D3D11 path. The two NVIDIA shims DXMT
# also ships (nvapi64, nvngx) are for DLSS and GPU-vendor queries - nothing to
# do with creating a device - so they are deliberately left out to keep the
# change small and the test clean.
FILES="d3d11.dll d3d10core.dll dxgi.dll winemetal.dll"

echo "==================================================="
echo "  Repair the Direct3D translation layer (DXMT)"
echo "==================================================="
echo ""

# --- sanity ------------------------------------------------------------------
fail=0
[ -d "$BOTTLE" ] || { echo "ERROR: bottle missing: $BOTTLE"; fail=1; }
[ -d "$LIB/DXMT/x64" ] || { echo "ERROR: DXMT 64-bit library missing: $LIB/DXMT/x64"; fail=1; }
[ -d "$LIB/DXMT/x32" ] || { echo "ERROR: DXMT 32-bit library missing: $LIB/DXMT/x32"; fail=1; }
if [ "$fail" = 1 ]; then
  echo ""
  echo "VOID - cannot run. Nothing was changed."
  echo "Press any key."; read -n 1; exit 1
fi

if pgrep -f "wineserver" >/dev/null 2>&1 || pgrep -if "steam.exe" >/dev/null 2>&1; then
  echo "Wine is still running. Run 'STOP everything.command' first, then re-run this."
  echo ""
  echo "VOID - nothing was changed."
  echo "Press any key."; read -n 1; exit 1
fi

# --- before ------------------------------------------------------------------
# Identify what each file currently IS, by checksum, not by guessing.
identify() {   # identify <file-on-disk> <arch-dir-x64|x32>
  local f="$1" arch="$2" m
  [ -f "$f" ] || { echo "absent"; return; }
  m=$(md5 -q "$f")
  [ "$m" = "$(md5 -q "$LIB/DXMT/$arch/$(basename "$f")" 2>/dev/null)" ] && { echo "DXMT"; return; }
  [ "$m" = "$(md5 -q "$LIB/DXVK/$arch/$(basename "$f")" 2>/dev/null)" ] && { echo "DXVK"; return; }
  echo "other"
}

echo "Current state of the bottle:"
for f in $FILES; do
  printf "  %-16s 64-bit: %-7s 32-bit: %s\n" "$f" \
    "$(identify "$SYS32/$f" x64)" "$(identify "$SYSWOW/$f" x32)"
done
echo ""

# --- back up -----------------------------------------------------------------
mkdir -p "$BACKUP/system32" "$BACKUP/syswow64"
for f in $FILES; do
  [ -f "$SYS32/$f" ]  && cp -p "$SYS32/$f"  "$BACKUP/system32/"  2>/dev/null
  [ -f "$SYSWOW/$f" ] && cp -p "$SYSWOW/$f" "$BACKUP/syswow64/"  2>/dev/null
done
cp -p "$BOTTLE/user.reg" "$BACKUP/user.reg" 2>/dev/null
echo "Backed up the files being replaced to:"
echo "  $BACKUP"
echo ""

# --- install a COMPLETE, matched DXMT set ------------------------------------
echo "Installing a complete matched DXMT set..."
for f in $FILES; do
  cp -f "$LIB/DXMT/x64/$f" "$SYS32/$f"  2>/dev/null && echo "  64-bit  $f"
  cp -f "$LIB/DXMT/x32/$f" "$SYSWOW/$f" 2>/dev/null && echo "  32-bit  $f"
done
echo ""

# --- make Wine actually prefer them ------------------------------------------
# Written straight into user.reg. Editing the file is safe here because no
# wineserver is running (checked above) - if one were, it would hold the
# registry in memory and overwrite this on exit.
#
# "native" means: use the DLL in system32, never Wine's own.
#
# winemetal is the ONE exception and must stay "builtin". It is only half a
# DLL: the .dll is a thin shim that must pair with winemetal.so (31 MB) built
# INTO Wine itself, and Wine only pairs the two for builtin DLLs. Forcing it
# native loads the shim with no engine behind it, so dxgi.dll - which imports
# winemetal - fails to load at all:
#     err:module:import_dll Library winemetal.dll ... not found
# and everything above it dies, including Steam's own UI. d3d11, d3d10core and
# dxgi have no .so counterpart, so native is correct for those three.
echo "Telling Wine which DLLs to prefer (permanent, in the bottle registry)..."
python3 - "$BOTTLE/user.reg" <<'PY'
import sys, re
path = sys.argv[1]
src  = open(path, encoding='utf-8', errors='surrogateescape').read()
want = {'d3d11': 'native', 'd3d10core': 'native', 'dxgi': 'native',
        'winemetal': 'builtin'}

m = re.search(r'^\[Software\\\\Wine\\\\DllOverrides\][^\n]*\n(?:#time=[^\n]*\n)?', src, re.M)
if not m:
    print("  VOID - DllOverrides key not found; registry left untouched.")
    sys.exit(1)

start, end = m.span()
block_end  = src.find('\n[', end)
if block_end == -1:
    block_end = len(src)
body = src[end:block_end]

for name in want:
    body = re.sub(r'^"%s"=.*\n' % re.escape(name), '', body, flags=re.M)
lines = ''.join('"%s"="%s"\n' % (n, v) for n, v in want.items())
body  = lines + body.lstrip('\n')

open(path, 'w', encoding='utf-8', errors='surrogateescape').write(src[:end] + body + src[block_end:])
for n, v in want.items():
    print('  set  %-10s = %s' % (n, v))
PY
REG_RC=$?
echo ""

# --- prove it ----------------------------------------------------------------
echo "Verifying (this is the part that matters)..."
ok=1
for f in $FILES; do
  a=$(identify "$SYS32/$f" x64); b=$(identify "$SYSWOW/$f" x32)
  printf "  %-16s 64-bit: %-7s 32-bit: %s\n" "$f" "$a" "$b"
  [ "$a" = "DXMT" ] || ok=0
  [ "$b" = "DXMT" ] || ok=0
done
natcount=$(grep -cE '^"(d3d11|d3d10core|dxgi)"="native"' "$BOTTLE/user.reg" 2>/dev/null)
bltcount=$(grep -cE '^"winemetal"="builtin"' "$BOTTLE/user.reg" 2>/dev/null)
echo "  registry: $natcount of 3 native, $bltcount of 1 builtin (winemetal)"
[ "$natcount" = "3" ] || ok=0
[ "$bltcount" = "1" ] || ok=0
[ "$REG_RC" = "0" ]   || ok=0

echo ""
if [ "$ok" = 1 ]; then
  echo "SUCCESS - the bottle now has one consistent DXMT stack, and Wine is"
  echo "told to use it however the game is launched."
  echo ""
  echo "Next: run your 'Play <game>.command' (make one with 'Add a game.command')."
else
  echo "VOID - the fix did NOT fully apply. Do not draw conclusions from a"
  echo "test run in this state. Restore from:"
  echo "  $BACKUP"
fi
echo ""
echo "Press any key to close."
read -n 1
