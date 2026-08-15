#!/bin/bash
# Decide whether a freshly built win32u.so is safe to install in place of
# Whisky's own. THE SINGLE COPY OF THIS CHECK.
#
#     ./verify-engine.sh <reference.so> <candidate.so>
#     exit 0 = equivalent and safe;  exit 1 = do not install
#
#
# WHY THIS FILE EXISTS
# --------------------
# This check used to live in TWO places - build-engine.sh and
# install-pointer-fix.sh - with slightly different contents. Then four import
# differences were investigated, found harmless, and written into only ONE of
# them. The other kept failing on them.
#
# The result: a correct build was rejected with
#
#     [FAIL] imports present in Whisky's but MISSING from ours:
#             _ceil _floor _roundf dyld_stub_binder
#     VOID - not equivalent to Whisky's engine.
#
# on someone else's Mac, and they reasonably concluded they had the wrong
# version of Whisky. Nothing was wrong with their build at all.
#
# The two copies had also drifted the other way: the installer checked the
# shm-surface code but not the rpath or CoreText, so running it on its own
# skipped the exact check that catches the "cannot find the FreeType font
# library" failure.
#
# It was a duplication bug, so the fix is to remove the duplication rather than
# patch the second copy. Both scripts now call this.
#
#
# ON THE FOUR "MISSING" IMPORTS
# -----------------------------
# Rather than trusting a hardcoded allowlist, this RE-CONFIRMS the reason each
# one is absent, every run. An allowlist says "we decided these are fine once";
# this asks "is that still true?"
#
#   _ceil, _floor, _roundf   clang -O2 emits these as single SSE4.1 roundsd
#                            instructions instead of calls. Confirmed by
#                            checking other libm imports (atan2, log, pow) are
#                            still present - if libm had genuinely gone missing
#                            those would be gone too.
#   dyld_stub_binder         Absent because the newer linker uses chained
#                            fixups instead of lazy binding. Confirmed by
#                            looking for LC_DYLD_CHAINED_FIXUPS in the binary.

set -u

REF="${1:-}"
NEW="${2:-}"

if [ -z "$REF" ] || [ -z "$NEW" ]; then
  echo "usage: $(basename "$0") <reference.so> <candidate.so>"; exit 2
fi
for f in "$REF" "$NEW"; do
  [ -f "$f" ] || { echo "  [FAIL] missing file: $f"; exit 1; }
done

ok=1
fail() { echo "  [FAIL] $*"; ok=0; }
pass() { echo "  [ ok ] $*"; }

nm -u  "$REF" 2>/dev/null | sort -u > /tmp/ve_i_ref.txt
nm -u  "$NEW" 2>/dev/null | sort -u > /tmp/ve_i_new.txt
nm -gU "$REF" 2>/dev/null | awk '{print $NF}' | sort -u > /tmp/ve_e_ref.txt
nm -gU "$NEW" 2>/dev/null | awk '{print $NF}' | sort -u > /tmp/ve_e_new.txt

echo "  imports : $(wc -l < /tmp/ve_i_ref.txt | tr -d ' ') reference, $(wc -l < /tmp/ve_i_new.txt | tr -d ' ') built"
echo "  exports : $(wc -l < /tmp/ve_e_ref.txt | tr -d ' ') reference, $(wc -l < /tmp/ve_e_new.txt | tr -d ' ') built"

# --- exports ----------------------------------------------------------------
# A MISSING export breaks whatever called it. An EXTRA one cannot - nothing in
# Whisky calls a symbol that did not exist in Whisky's own build.
missing_exports=$(comm -23 /tmp/ve_e_ref.txt /tmp/ve_e_new.txt)
extra_exports=$(comm -13 /tmp/ve_e_ref.txt /tmp/ve_e_new.txt | tr '\n' ' ')
if [ -n "$missing_exports" ]; then
  fail "exports missing from the build:"; echo "$missing_exports" | sed 's/^/          /'
else
  pass "no missing exports${extra_exports:+ (extra, harmless: $extra_exports)}"
fi

# --- imports, with the reasons re-checked -----------------------------------
libm_intact=0
for s in _atan2 _log _pow; do grep -qx "$s" /tmp/ve_i_new.txt && libm_intact=$((libm_intact+1)); done
chained=$(otool -l "$NEW" 2>/dev/null | grep -c "CHAINED_FIXUPS")

unexplained=""
for sym in $(comm -23 /tmp/ve_i_ref.txt /tmp/ve_i_new.txt); do
  case "$sym" in
    _ceil|_floor|_roundf)
      if [ "$libm_intact" -ge 2 ]; then
        pass "missing but explained: $sym (inlined; libm still linked)"
      else
        fail "$sym missing AND libm looks absent - that is a real problem"
      fi ;;
    dyld_stub_binder)
      if [ "$chained" -gt 0 ]; then
        pass "missing but explained: $sym (binary uses chained fixups)"
      else
        fail "$sym missing and no chained fixups - unexplained"
      fi ;;
    *) unexplained="$unexplained $sym" ;;
  esac
done
if [ -n "$unexplained" ]; then
  fail "UNEXPLAINED missing imports:$unexplained"
elif [ -z "$(comm -23 /tmp/ve_i_ref.txt /tmp/ve_i_new.txt)" ]; then
  pass "no missing imports"
fi

# --- the build must actually contain the fix --------------------------------
if strings -a "$NEW" 2>/dev/null | grep -q "enable %u stub!"; then
  fail "still contains the stub - the pointer fix is NOT in this build"
else
  pass "pointer API implemented (stub absent)"
fi

# --- CrossOver-derived, like Whisky's ---------------------------------------
for s in create_shm_surface process_surface_message; do
  if strings -a "$NEW" 2>/dev/null | grep -q "$s"; then
    pass "$s present (CrossOver-derived, as Whisky's is)"
  else
    fail "$s missing - this looks like a vanilla-Wine build, which cannot work"
  fi
done

# --- font backend compiled in -----------------------------------------------
if otool -L "$NEW" 2>/dev/null | grep -q CoreText; then
  pass "CoreText linked (font backend compiled in)"
else
  fail "CoreText not linked - the font backend was left out of this build"
fi

# --- can it FIND its libraries at runtime? ----------------------------------
# Compiled-in is not the same as loadable. A missing rpath produced "Wine cannot
# find the FreeType font library" while every symbol-level check passed.
ref_rp=$(otool -l "$REF" 2>/dev/null | grep -A2 LC_RPATH | grep "path " | awk '{print $2}' | sort | tr '\n' ' ')
new_rp=$(otool -l "$NEW" 2>/dev/null | grep -A2 LC_RPATH | grep "path " | awk '{print $2}' | sort | tr '\n' ' ')
if [ "$ref_rp" = "$new_rp" ]; then
  pass "rpaths match Whisky's: $new_rp"
else
  fail "rpath mismatch - libraries will not load at runtime"
  echo "          whisky: $ref_rp"
  echo "          ours  : $new_rp"
fi

[ "$ok" = 1 ] && exit 0 || exit 1
