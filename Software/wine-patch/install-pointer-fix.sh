#!/bin/bash
# Install the patched win32u.so into Whisky's Wine engine.
#
# Run build-engine.sh FIRST. This script re-runs the same import-parity
# check itself and refuses to install anything that fails it, because an
# unverified engine turns every later test result into noise: a black screen
# from a binary that was never equivalent proves nothing about the patch.
#
# WHAT GETS REPLACED
# ------------------
# Only win32u.so, the Unix-side library. The patch adds no exports and removes
# none, so the PE-side win32u.dll (the thin syscall-thunk stub) is unchanged -
# this script compares it and only installs it if it genuinely differs.
# user32.dll is NOT touched at all: CodeWeavers implemented this entirely
# inside win32u, unlike the community patch which also modified user32.
#
# Whisky's original is backed up before anything is written, and
# 'uninstall' puts it back.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# Engine location and architecture are discovered rather than hardcoded, so this
# still finds the engine after a move to CrossOver. See engine-detect.sh.
. "$HERE/engine-detect.sh"
if [ "$ENGINE_FOUND" != yes ]; then
  echo "No Wine engine found. Open Whisky once to download it, or install CrossOver."
  echo ""; echo "VOID - nothing was changed."; exit 1
fi
# Refuse to install into an engine that cannot execute on this Mac. Writing a
# correct library into an unrunnable engine produces a loader error that reads
# exactly like a broken patch, and that wrong diagnosis is expensive.
if [ "$ENGINE_NEEDS_ROSETTA" = yes ] && [ "$ROSETTA_PRESENT" = no ]; then
  echo "This engine is $ENGINE_ARCH, this Mac is $HOST_ARCH, and Rosetta 2 is absent."
  echo "The engine cannot run, so patching it would prove nothing. Install Rosetta"
  echo "(softwareupdate --install-rosetta) or move to an ARM64-native engine."
  echo ""; echo "VOID - nothing was changed."; exit 1
fi
TARGET_SO="$ENGINE_WIN32U"
TARGET_DLL="$ENGINE_WIN_DIR/win32u.dll"
BUILT_SO="$HERE/crossover-src/sources/wine/dlls/win32u/win32u.so"
BUILT_DLL="$HERE/crossover-src/sources/wine/dlls/win32u/${ENGINE_ARCH}-windows/win32u.dll"
ORIG="$HERE/whisky-original"

# Imports that legitimately differ, with the reason each one is non-functional.
# Anything NOT on this list is treated as a real missing capability and blocks
# the install. The list is deliberately short and specific - it exists so that
# "explained difference" and "unexplained difference" cannot be confused.
#
#   ceil/floor/roundf  clang -O2 emits these as single SSE4.1 roundsd
#                      instructions instead of calls. Verified that other libm
#                      imports (atan2, log, pow) are still present, so libm
#                      linkage is intact - only the inlinable ones vanished.
#   dyld_stub_binder   Whisky's build uses classic LC_DYLD_INFO lazy binding,
#                      which needs this symbol; ours uses the newer
#                      LC_DYLD_CHAINED_FIXUPS, which does not. Linking mode,
#                      not behaviour. (Confirmed via otool -l on both.)
BENIGN_MISSING="_ceil _floor _roundf dyld_stub_binder"

usage() { echo "usage: $(basename "$0") [install|uninstall|status]"; exit 2; }
MODE="${1:-install}"

# --- refuse to touch a running engine ---------------------------------------
if pgrep -f "wineserver" >/dev/null 2>&1 || pgrep -if "steam.exe" >/dev/null 2>&1; then
  echo "Wine is still running. Run 'STOP everything.command' first."
  echo ""; echo "VOID - nothing was changed."; exit 1
fi

# ---------------------------------------------------------------- status ----
show_status() {
  echo "Current engine:"
  if [ ! -f "$TARGET_SO" ]; then echo "  win32u.so MISSING"; return; fi
  printf "  %-14s %s bytes\n" "win32u.so" "$(stat -f %z "$TARGET_SO")"
  if strings -a "$TARGET_SO" 2>/dev/null | grep -q "enable %u stub!"; then
    echo "  pointer API : STUBBED (stock Wine - clicks will not work)"
  else
    echo "  pointer API : IMPLEMENTED (patched)"
  fi
  [ -f "$ORIG/win32u.so" ] && echo "  backup      : $ORIG/win32u.so" \
                           || echo "  backup      : none yet"
}

if [ "$MODE" = "status" ]; then show_status; exit 0; fi

# ------------------------------------------------------------- uninstall ----
if [ "$MODE" = "uninstall" ]; then
  if [ ! -f "$ORIG/win32u.so" ]; then
    echo "No backup found at $ORIG - nothing to restore."; exit 1
  fi
  cp -p "$ORIG/win32u.so" "$TARGET_SO" || { echo "VOID - restore failed"; exit 1; }
  [ -f "$ORIG/win32u.dll" ] && cp -p "$ORIG/win32u.dll" "$TARGET_DLL"
  echo "Restored Whisky's original engine."
  echo ""; show_status; exit 0
fi

[ "$MODE" = "install" ] || usage

# --------------------------------------------------------------- install ----
echo "==================================================="
echo "  Install the Unity pointer fix into Whisky's Wine"
echo "==================================================="
echo ""

[ -f "$BUILT_SO" ] || { echo "No build found at $BUILT_SO"; echo "Run ./build-engine.sh first."; echo ""; echo "VOID"; exit 1; }

# --- gate: parity with whatever is currently installed ----------------------
# Compare against the ORIGINAL if we have one, else against what is live now.
REF="$TARGET_SO"
[ -f "$ORIG/win32u.so" ] && REF="$ORIG/win32u.so"

echo "Verifying the build against Whisky's engine..."
if ! "$HERE/verify-engine.sh" "$REF" "$BUILT_SO"; then
  echo ""
  echo "VOID - the build is not equivalent to Whisky's engine. Nothing installed."
  exit 1
fi
echo ""

# Can we actually write to the engine? Check BEFORE touching anything, so this
# fails in one second with a usable message instead of at the final copy.
if [ ! -w "$TARGET_SO" ]; then
  OWNER=$(stat -f '%Su' "$TARGET_SO" 2>/dev/null); ME=$(whoami)
  echo "Cannot write to Whisky's engine:"
  echo "  $TARGET_SO"
  echo "  owned by: $OWNER      you are: $ME"
  echo ""
  if [ "$OWNER" != "$ME" ]; then
    echo "  Whisky's files belong to $OWNER. Take ownership of your own app data:"
    echo ""
    echo "    sudo chown -R \"$ME\" \"$HOME/Library/Application Support/com.franke.Whisky\""
  else
    echo "  You own it but it is read-only:"
    echo ""
    echo "    chmod u+w \"$TARGET_SO\""
  fi
  echo ""
  echo "  Do NOT re-run this whole script with sudo. That would put root-owned"
  echo "  files in your home folder and Whisky could no longer manage them."
  echo ""
  echo "VOID - nothing was changed."
  exit 1
fi

# --- back up ----------------------------------------------------------------
mkdir -p "$ORIG"
if [ ! -f "$ORIG/win32u.so" ]; then
  cp -p "$TARGET_SO"  "$ORIG/win32u.so"
  cp -p "$TARGET_DLL" "$ORIG/win32u.dll" 2>/dev/null
  echo "Backed up Whisky's original engine to:"
  echo "  $ORIG"
else
  echo "Original already backed up (keeping the first one, which is stock)."
fi
echo ""

# --- install ----------------------------------------------------------------
cp -f "$BUILT_SO" "$TARGET_SO" || { echo "VOID - copy failed"; exit 1; }
echo "Installed win32u.so"

# The PE side only needs replacing if the syscall numbering changed. Say which
# of the three cases actually happened - an earlier version printed "unchanged"
# even when the file did not exist, which was a comforting lie.
if [ ! -f "$BUILT_DLL" ]; then
  echo "win32u.dll: no PE build found, leaving Whisky's in place"
  echo "            (fine - the .so is what carries the fix)"
elif cmp -s "$BUILT_DLL" "$TARGET_DLL"; then
  echo "win32u.dll: identical to Whisky's, nothing to do"
else
  cp -f "$BUILT_DLL" "$TARGET_DLL" && echo "win32u.dll: installed (it differed)"
fi
echo ""

# --- prove it ---------------------------------------------------------------
echo "Verifying what is now live..."
ok=1
strings -a "$TARGET_SO" | grep -q "enable %u stub!" && { echo "  [FAIL] stub still present"; ok=0; } \
                                                    || echo "  [ ok ] stub is gone"
nm -a "$TARGET_SO" 2>/dev/null | grep -q "_NtUserEnableMouseInPointer" \
  && echo "  [ ok ] NtUserEnableMouseInPointer exported" || { echo "  [FAIL] symbol missing"; ok=0; }
otool -L "$TARGET_SO" 2>/dev/null | grep -q CoreText \
  && echo "  [ ok ] CoreText linked (font backend compiled in)" || { echo "  [FAIL] no CoreText"; ok=0; }

echo ""
if [ "$ok" = 1 ]; then
  echo "SUCCESS - Whisky's engine now implements the Windows pointer API."
  echo ""
  echo "Next: launch your game and try clicking."
  echo "To undo:  ./install-pointer-fix.sh uninstall"
else
  echo "VOID - something is wrong with the installed engine. Restore with:"
  echo "  ./install-pointer-fix.sh uninstall"
  exit 1
fi
