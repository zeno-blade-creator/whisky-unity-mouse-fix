#!/bin/bash
# Install the patched win32u.so into Whisky's Wine engine.
#
# Run build-and-verify.sh FIRST. This script re-runs the same import-parity
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
WINE="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine"
TARGET_SO="$WINE/lib/wine/x86_64-unix/win32u.so"
TARGET_DLL="$WINE/lib/wine/x86_64-windows/win32u.dll"
BUILT_SO="$HERE/wine-11.0/dlls/win32u/win32u.so"
BUILT_DLL="$HERE/wine-11.0/dlls/win32u/win32u.dll"
ORIG="$HERE/whisky-original"

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

[ -f "$BUILT_SO" ] || { echo "No build found at $BUILT_SO"; echo "Run ./build-and-verify.sh first."; echo ""; echo "VOID"; exit 1; }

# --- gate: parity with whatever is currently installed ----------------------
# Compare against the ORIGINAL if we have one, else against what is live now.
REF="$TARGET_SO"
[ -f "$ORIG/win32u.so" ] && REF="$ORIG/win32u.so"

echo "Verifying the build against Whisky's engine..."
nm -u "$REF"      2>/dev/null | sort -u > /tmp/i_ref.txt
nm -u "$BUILT_SO" 2>/dev/null | sort -u > /tmp/i_new.txt
nm -gU "$REF"      2>/dev/null | awk '{print $NF}' | sort -u > /tmp/e_ref.txt
nm -gU "$BUILT_SO" 2>/dev/null | awk '{print $NF}' | sort -u > /tmp/e_new.txt
missing=$(comm -23 /tmp/i_ref.txt /tmp/i_new.txt)
expdiff=$(diff /tmp/e_ref.txt /tmp/e_new.txt | grep -c "^[<>]")

echo "  imports: $(wc -l < /tmp/i_ref.txt | tr -d ' ') reference vs $(wc -l < /tmp/i_new.txt | tr -d ' ') built"
echo "  exports: $(wc -l < /tmp/e_ref.txt | tr -d ' ') reference vs $(wc -l < /tmp/e_new.txt | tr -d ' ') built ($expdiff differences)"
if [ -n "$missing" ] || [ "$expdiff" != "0" ]; then
  echo ""
  echo "  Missing imports:"; echo "${missing:-    (none)}" | sed 's/^/    /'
  echo ""
  echo "VOID - the build is not equivalent to Whisky's engine. Nothing installed."
  exit 1
fi

# The build must actually contain the fix, not merely be equivalent.
if strings -a "$BUILT_SO" | grep -q "enable %u stub!"; then
  echo ""
  echo "VOID - the built engine still contains the stub. The patch did not take."
  exit 1
fi
echo "  pointer API implemented in the build: yes"
echo ""

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

if [ -f "$BUILT_DLL" ] && ! cmp -s "$BUILT_DLL" "$TARGET_DLL"; then
  cp -f "$BUILT_DLL" "$TARGET_DLL" && echo "Installed win32u.dll (it differed)"
else
  echo "win32u.dll unchanged - left alone (no exports were added or removed)"
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
  echo "Next: run 'Play PEAK.command' and try clicking."
  echo "To undo:  ./install-pointer-fix.sh uninstall"
else
  echo "VOID - something is wrong with the installed engine. Restore with:"
  echo "  ./install-pointer-fix.sh uninstall"
  exit 1
fi
