#!/bin/bash
# Build a win32u.so for Whisky that implements the Windows pointer API, so
# Unity 6 games register mouse clicks.
#
#
# WHY THIS BUILDS CROSSOVER'S SOURCE AND NOT VANILLA WINE
# -------------------------------------------------------
# The obvious approach - take vanilla wine-11.0, apply the pointer patch,
# rebuild - CANNOT produce a drop-in replacement, and it took a measurement to
# find out why.
#
# Whisky's engine is not vanilla Wine. Compare the two shipped binaries:
#
#     Whisky win32u.so  vs  CrossOver 26.3 win32u.so
#       imports: 164 vs 164   -> ZERO differences
#       exports: 504 vs 505   -> differs by one symbol
#
# Whisky's Wine IS CrossOver's Wine. (Whisky's own site says "built on top of
# CrossOver"; this confirms it at the binary level.) It carries CodeWeavers'
# shared-memory window-surface code - create_shm_surface,
# process_surface_message, and the NtCreateSection/NtOpenProcess machinery
# behind them - which vanilla Wine has never had.
#
# A vanilla build therefore comes out ~8 imports short and silently missing a
# feature the rest of Whisky's engine expects. It would probably appear to work
# and then fail somewhere unrelated and unexplainable.
#
# Whisky's engine is based on an OLDER CrossOver, from before CodeWeavers
# implemented the pointer API - which is exactly why it still has the stub:
#
#     Whisky     "enable %u stub!"  + ERROR_CALL_NOT_IMPLEMENTED, returns FALSE
#     CrossOver  "enable %u", lock cmpxchg into a global, returns TRUE
#
# So the fix is not to patch anything. It is to build the NEWER CrossOver
# source, which already contains the implementation, and take its win32u.so.
#
# All of this is LGPL 2.1+. CodeWeavers publishes these sources because the
# licence requires it; see crossover-sources-26.3.0.tar.gz.
#
#
# THE FOUR ENVIRONMENT TRAPS THIS SCRIPT HANDLES
# ----------------------------------------------
# Each one failed in a way that pointed nowhere near its actual cause:
#
#   1. Whisky lives under "Application Support" - a path WITH A SPACE. Passing
#      that in -L splits it into two broken arguments, and configure reports
#      "C compiler cannot create executables", which reads like a broken
#      toolchain. Fixed with a space-free symlink.
#
#   2. macOS ships bison 2.3 (2006) at /usr/bin/bison; Wine needs 3.0+.
#      Homebrew's bison 3.8 is keg-only so it is deliberately NOT on PATH.
#      Inheriting ambient PATH silently picks the wrong one.
#
#   3. Build-time tools link Whisky's libfreetype, whose install name is a bare
#      filename. DYLD_LIBRARY_PATH does not help, because SIP STRIPS DYLD_*
#      variables when make invokes recipes through /bin/sh. Fixed by putting a
#      symlink where dyld already looks - the tree root.
#
#   4. Wine's soname detection mis-parses that same bare install name and bakes
#      the whole otool -L line into config.h:
#          #define SONAME_LIBFREETYPE "  libfreetype.dylib (compatibility ...)"
#      Wine then dlopen()s that string at runtime, fails, and loses the font
#      backend - compiled in but dead. Note that an imports check CANNOT catch
#      this: dlopen appears either way. Overridden explicitly, and gated below.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$HERE/crossover-src/sources/wine"
WLIB_REAL="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/lib"
WLIB="$HOME/.whisky-wine-lib"          # trap 1: space-free path
REFERENCE="$WLIB/wine/x86_64-unix/win32u.so"
FT_HEADERS="/opt/homebrew/include/freetype2"
JOBS=$(sysctl -n hw.ncpu)

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"   # trap 2

ln -sfn "$WLIB_REAL" "$WLIB" 2>/dev/null

echo "==================================================="
echo "  Build CrossOver 26.3's win32u.so for Whisky"
echo "==================================================="
echo ""

# --- preconditions -----------------------------------------------------------
fail=0
[ -d "$TREE" ] || { echo "ERROR: CrossOver source tree missing: $TREE"
                    echo "       Extract it from crossover-sources-26.3.0.tar.gz:"
                    echo "         tar xzf crossover-sources-26.3.0.tar.gz -C crossover-src sources/wine"; fail=1; }
[ -f "$REFERENCE" ] || { echo "ERROR: Whisky reference engine missing"; fail=1; }
[ -f "$WLIB/libfreetype.6.dylib" ] || { echo "ERROR: x86_64 libfreetype missing in Whisky"; fail=1; }
[ -d "$FT_HEADERS" ] || { echo "ERROR: freetype headers missing. brew install freetype"; fail=1; }
[ "$fail" = 0 ] || { echo ""; echo "VOID - preconditions not met."; exit 1; }

# --- toolchain gate ----------------------------------------------------------
BISON_V=$(bison --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
echo "Toolchain:"
printf "  %-8s %s (%s)\n" "bison" "$(command -v bison)" "$BISON_V"
printf "  %-8s %s\n" "mingw" "$(command -v x86_64-w64-mingw32-gcc)"
if [ -z "${BISON_V%%.*}" ] || [ "${BISON_V%%.*}" -lt 3 ] 2>/dev/null; then
  echo ""; echo "VOID - bison $BISON_V too old (need 3.0+):  brew install bison"; exit 1
fi
command -v x86_64-w64-mingw32-gcc >/dev/null || {
  echo ""; echo "VOID - mingw-w64 missing:  brew install mingw-w64"; exit 1; }
echo ""

# --- trap 3: dyld cannot find a bare-named dylib under SIP -------------------
ln -sfn "$WLIB/libfreetype.6.dylib" "$TREE/libfreetype.dylib"
ln -sfn "$WLIB/libfreetype.6.dylib" "$TREE/libfreetype.6.dylib"

# --- configure ---------------------------------------------------------------
# Match Whisky's own dlopen target exactly. Whisky's engine loads
# "libfreetype.6.dylib" - confirmed by reading the string out of its binary -
# so that is what we bake in, rather than whatever configure guesses.
echo "[1/4] configure..."
cd "$TREE" || exit 1
./configure \
  --host=x86_64-apple-darwin --build=x86_64-apple-darwin \
  CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
  --enable-archs=x86_64 --without-x --disable-tests \
  FREETYPE_CFLAGS="-I$FT_HEADERS" \
  FREETYPE_LIBS="-L$WLIB -lfreetype" \
  LDFLAGS="-L$WLIB" \
  ac_cv_lib_soname_freetype=libfreetype.6.dylib \
  > "$HERE/cx-configure.log" 2>&1 \
  || { echo "  configure FAILED - see cx-configure.log"; echo ""; echo "VOID"; exit 1; }

# --- gate 1: what did configure actually detect? -----------------------------
echo "[2/4] checking configure results..."
gate=1
FT_SONAME=$(grep -E '^#define SONAME_LIBFREETYPE' include/config.h | cut -d'"' -f2)
WHISKY_SONAME=$(strings -a "$REFERENCE" | grep -E '^libfreetype[0-9.]*\.dylib$' | head -1)

if [ -z "$FT_SONAME" ]; then
  echo "  [FAIL] freetype not found -> no font backend"; gate=0
elif [ "$FT_SONAME" != "$WHISKY_SONAME" ]; then
  echo "  [FAIL] soname '$FT_SONAME' != Whisky's '$WHISKY_SONAME'"; gate=0
elif echo "$FT_SONAME" | grep -q '[ 	(]'; then
  echo "  [FAIL] soname is mis-parsed (contains whitespace/parens): '$FT_SONAME'"; gate=0
else
  echo "  [ ok ] freetype soname matches Whisky exactly: $FT_SONAME"
fi
grep -qE '^#define SONAME_LIBMOLTENVK|^#define SONAME_LIBVULKAN' include/config.h \
  && echo "  [ ok ] Vulkan/MoltenVK found" \
  || echo "  [warn] no Vulkan/MoltenVK (DXMT uses Metal, so this is survivable)"

# The whole point of using this tree: the fix should already be in the source.
grep -q "enable_mouse_in_pointer" dlls/win32u/input.c \
  && echo "  [ ok ] pointer implementation present in source" \
  || { echo "  [FAIL] this source has no pointer implementation"; gate=0; }

[ "$gate" = 1 ] || { echo ""; echo "VOID - nothing was built."; exit 1; }

# --- build -------------------------------------------------------------------
echo "[3/4] make -j$JOBS (this takes a while)..."
make -j"$JOBS" > "$HERE/cx-build.log" 2>&1 || {
  echo "  make FAILED. Last errors:"
  grep -iE "error:|Abort trap|Library not loaded" "$HERE/cx-build.log" | tail -12 | sed 's/^/    /'
  echo ""; echo "VOID"; exit 1; }

BUILT="$TREE/dlls/win32u/win32u.so"
[ -f "$BUILT" ] || { echo "  no win32u.so produced"; echo ""; echo "VOID"; exit 1; }
echo "  built: $(stat -f %z "$BUILT") bytes"

# --- gate 2: equivalence with Whisky's engine --------------------------------
echo "[4/4] verifying against Whisky's engine..."
nm -u  "$REFERENCE" 2>/dev/null | sort -u > /tmp/i_ref.txt
nm -u  "$BUILT"     2>/dev/null | sort -u > /tmp/i_new.txt
nm -gU "$REFERENCE" 2>/dev/null | awk '{print $NF}' | sort -u > /tmp/e_ref.txt
nm -gU "$BUILT"     2>/dev/null | awk '{print $NF}' | sort -u > /tmp/e_new.txt

missing_imports=$(comm -23 /tmp/i_ref.txt /tmp/i_new.txt)
missing_exports=$(comm -23 /tmp/e_ref.txt /tmp/e_new.txt)

echo "  imports : $(wc -l < /tmp/i_ref.txt|tr -d ' ') reference, $(wc -l < /tmp/i_new.txt|tr -d ' ') built"
echo "  exports : $(wc -l < /tmp/e_ref.txt|tr -d ' ') reference, $(wc -l < /tmp/e_new.txt|tr -d ' ') built"

ok=1
if [ -n "$missing_imports" ]; then
  echo "  [FAIL] imports present in Whisky's but MISSING from ours:"
  echo "$missing_imports" | sed 's/^/          /'; ok=0
else
  echo "  [ ok ] no missing imports"
fi
# Extra exports are harmless (nothing calls a symbol that did not exist before);
# MISSING exports would break callers, so only those are fatal.
if [ -n "$missing_exports" ]; then
  echo "  [FAIL] exports MISSING from ours:"; echo "$missing_exports" | sed 's/^/          /'; ok=0
else
  extra=$(comm -13 /tmp/e_ref.txt /tmp/e_new.txt | tr '\n' ' ')
  echo "  [ ok ] no missing exports${extra:+ (extra, harmless: $extra)}"
fi
strings -a "$BUILT" | grep -q "enable %u stub!" \
  && { echo "  [FAIL] still contains the stub"; ok=0; } \
  || echo "  [ ok ] pointer API implemented (stub absent)"
otool -L "$BUILT" 2>/dev/null | grep -q CoreText \
  && echo "  [ ok ] CoreText linked (font backend compiled in)" \
  || { echo "  [FAIL] CoreText not linked"; ok=0; }

echo ""
if [ "$ok" = 1 ]; then
  echo "PASS - equivalent to Whisky's engine, plus the pointer implementation."
  echo ""
  echo "Install with:  ./install-pointer-fix.sh"
else
  echo "VOID - not equivalent to Whisky's engine. Do NOT install it; a test run"
  echo "       with this binary would prove nothing."
  exit 1
fi
