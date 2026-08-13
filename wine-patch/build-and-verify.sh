#!/bin/bash
# Build the patched wine-11.0 and PROVE the result is equivalent to Whisky's
# own engine before anyone is allowed to install it.
#
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# A previous attempt built this patch and produced an engine that crashed. The
# patch source was later exonerated - the fault was in HOW it was configured:
#
#     ./configure ... --without-x --disable-tests --without-freetype
#
# --without-freetype does far more than drop font rasterisation. On macOS,
# Wine's entire font backend lives in dlls/win32u/freetype.c, and that file is
# also where CoreText system-font enumeration lives. Excluding it produced a
# win32u.so with NO font backend at all, missing 46 imports that Whisky's has:
# CoreText, CoreFoundation, and - because Wine dlopen()s freetype and Vulkan at
# runtime - dlopen/dlsym/dlclose too.
#
# That difference was invisible to the check that was actually run at the time:
# EXPORTED symbols matched (504 = 504), because exports are the DLL's public
# API and do not change. It is the IMPORTS that reveal what was compiled in.
#
# So this script gates on imports, and refuses to hand over a build that does
# not match. A build that cannot be proven equivalent is reported VOID, never
# "probably fine".
#
#
# THE DEPENDENCY TRICK
# --------------------
# This is an Apple Silicon Mac, but Whisky's Wine is x86_64 (it runs under
# Rosetta), so this has to be an x86_64 build - and Homebrew's libraries are
# arm64 and cannot be linked. The way out is that Whisky's Wine SHIPS the exact
# x86_64 libraries it was built against, right inside itself:
#
#     Libraries/Wine/lib/libfreetype.dylib    x86_64
#     Libraries/Wine/lib/libMoltenVK.dylib    x86_64
#
# Building against those gives architecture parity by construction. Headers are
# architecture-independent, so Homebrew's freetype headers are fine.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$HERE/wine-11.0"
PRISTINE="$HERE/pristine"
WLIB_REAL="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/lib"

# Whisky lives under "Application Support" - a path WITH A SPACE. Compiler flags
# like -L are split on whitespace when configure passes them to clang, so the
# space turns one -L into two broken arguments and every compile test fails with
# the maximally unhelpful "C compiler cannot create executables". A space-free
# symlink sidesteps it entirely.
WLIB="$HOME/.whisky-wine-lib"
ln -sfn "$WLIB_REAL" "$WLIB" 2>/dev/null

REFERENCE="$WLIB/wine/x86_64-unix/win32u.so"
FT_HEADERS="/opt/homebrew/include/freetype2"
JOBS=$(sysctl -n hw.ncpu)

echo "==================================================="
echo "  Build patched wine-11.0 and verify against Whisky"
echo "==================================================="
echo ""

# --- preconditions -----------------------------------------------------------
fail=0
[ -d "$TREE" ]            || { echo "ERROR: source tree missing: $TREE"; fail=1; }
[ -f "$REFERENCE" ]       || { echo "ERROR: Whisky reference win32u.so missing"; fail=1; }
[ -f "$WLIB/libfreetype.dylib" ] || { echo "ERROR: x86_64 libfreetype missing in Whisky"; fail=1; }
[ -d "$FT_HEADERS" ]      || { echo "ERROR: freetype headers missing ($FT_HEADERS). brew install freetype"; fail=1; }
grep -q "enable_mouse_in_pointer" "$TREE/dlls/win32u/input.c" 2>/dev/null \
  || { echo "ERROR: tree is not patched. Run apply-pointer-patch.py first."; fail=1; }
[ "$fail" = 0 ] || { echo ""; echo "VOID - preconditions not met. Nothing was built."; exit 1; }

echo "Reference engine : $REFERENCE"
echo "Building with    : $JOBS jobs"
echo ""

# --- configure ---------------------------------------------------------------
# FREETYPE_* are passed explicitly rather than via pkg-config, because
# pkg-config would hand back Homebrew's arm64 -L path and the link would fail
# in a confusing way.
echo "[1/4] configure..."
cd "$TREE" || exit 1
./configure \
  --host=x86_64-apple-darwin --build=x86_64-apple-darwin \
  CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
  --enable-archs=x86_64 \
  --without-x \
  --disable-tests \
  FREETYPE_CFLAGS="-I$FT_HEADERS" \
  FREETYPE_LIBS="-L$WLIB -lfreetype" \
  LDFLAGS="-L$WLIB" \
  > "$HERE/configure-fixed.log" 2>&1
if [ $? -ne 0 ]; then
  echo "  configure FAILED - see configure-fixed.log"
  echo ""; echo "VOID"; exit 1
fi

# --- gate 1: did configure actually find what we need? -----------------------
echo "[2/4] checking what configure detected..."
gate1=1
if grep -qE '^#define SONAME_LIBFREETYPE' include/config.h; then
  echo "  [ ok ] freetype found -> font backend WILL be compiled in"
else
  echo "  [FAIL] SONAME_LIBFREETYPE undefined -> no font backend (this is the old bug)"
  gate1=0
fi
if grep -qE '^#define SONAME_LIBMOLTENVK|^#define SONAME_LIBVULKAN' include/config.h; then
  echo "  [ ok ] Vulkan/MoltenVK found"
else
  echo "  [warn] no Vulkan/MoltenVK - acceptable (DXMT uses Metal), but noted"
fi
if [ "$gate1" = 0 ]; then
  echo ""
  echo "VOID - configure did not pick up freetype. Building now would repeat the"
  echo "       original mistake. Nothing was built."
  exit 1
fi

# --- build -------------------------------------------------------------------
echo "[3/4] make (this takes a while)..."
make -j"$JOBS" > "$HERE/build-fixed.log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "  make FAILED (exit $rc). Last errors:"
  grep -iE "error:" "$HERE/build-fixed.log" | tail -15 | sed 's/^/    /'
  echo ""; echo "VOID"; exit 1
fi
BUILT="$TREE/dlls/win32u/win32u.so"
[ -f "$BUILT" ] || { echo "  build produced no win32u.so"; echo ""; echo "VOID"; exit 1; }
echo "  built: $BUILT ($(stat -f %z "$BUILT") bytes)"

# --- gate 2: import parity ---------------------------------------------------
# The check that would have caught the original failure.
echo "[4/4] verifying against Whisky's engine..."
nm -u "$REFERENCE" 2>/dev/null | sort -u > /tmp/ref_imports.txt
nm -u "$BUILT"     2>/dev/null | sort -u > /tmp/new_imports.txt
missing=$(comm -23 /tmp/ref_imports.txt /tmp/new_imports.txt)
extra=$(comm -13 /tmp/ref_imports.txt /tmp/new_imports.txt)

nm -gU "$REFERENCE" 2>/dev/null | awk '{print $NF}' | sort -u > /tmp/ref_exports.txt
nm -gU "$BUILT"     2>/dev/null | awk '{print $NF}' | sort -u > /tmp/new_exports.txt
exp_diff=$(diff /tmp/ref_exports.txt /tmp/new_exports.txt | grep -c "^[<>]")

echo "  exports : $(wc -l < /tmp/ref_exports.txt | tr -d ' ') reference, $(wc -l < /tmp/new_exports.txt | tr -d ' ') built, $exp_diff differences"
echo "  imports : $(wc -l < /tmp/ref_imports.txt | tr -d ' ') reference, $(wc -l < /tmp/new_imports.txt | tr -d ' ') built"

gate2=1
if [ -n "$missing" ]; then
  echo ""
  echo "  MISSING imports (present in Whisky's, absent in ours) - this means"
  echo "  something was NOT compiled in:"
  echo "$missing" | sed 's/^/    /'
  gate2=0
fi
[ "$exp_diff" != "0" ] && { echo "  export sets differ by $exp_diff symbols"; gate2=0; }

echo ""
echo "  frameworks linked by our build:"
otool -L "$BUILT" 2>/dev/null | tail -n +2 | grep -oE "(CoreText|AppKit|CoreFoundation|libSystem)" | sort -u | sed 's/^/    /'

echo ""
if [ "$gate2" = 1 ]; then
  echo "PASS - the built win32u.so is import- and export-equivalent to Whisky's"
  echo "       engine, and additionally contains the pointer implementation."
  echo ""
  echo "Install it with:  ./install-pointer-fix.sh"
else
  echo "VOID - the build is NOT equivalent to Whisky's engine. Do NOT install it."
  echo "       A test run with this binary would prove nothing."
  exit 1
fi
