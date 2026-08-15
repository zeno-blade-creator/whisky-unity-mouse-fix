#!/bin/bash
# One-command installer: makes Unity 6 games respond to mouse clicks in Whisky.
#
# Run it with:
#     ./install.sh
#
# It checks what you have, offers to install anything missing, downloads the
# source, builds it, proves the result is sound, and installs it. Roughly 20
# minutes, most of which is the computer compiling while you do something else.
#
# It will not install anything it cannot verify. If a check fails it stops and
# tells you why, rather than leaving you with a half-working setup.
#
# To undo everything afterwards:
#     ./install-pointer-fix.sh uninstall

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TARBALL_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz"
TARBALL="$HERE/crossover-sources-26.3.0.tar.gz"
SRC="$HERE/crossover-src"
WHISKY_LIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries"

say()  { echo "$@"; }
step() { echo ""; echo "=== $* ==="; }
die()  { echo ""; echo "STOPPED: $*"; echo ""; exit 1; }

ask() {  # ask "question" -> 0 if yes
  local reply
  printf "%s [y/N] " "$1"
  read -r reply
  [ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

echo "==========================================================="
echo "  Mouse-click fix for Unity 6 games in Whisky (macOS)"
echo "==========================================================="
say ""
say "Unity 6 games ask Windows for a newer kind of mouse message."
say "Whisky's Wine says \"not implemented\", so the cursor moves but"
say "nothing ever clicks. This installs an engine that implements it."

# --- 0. sanity --------------------------------------------------------------
step "Checking your Mac"
[ "$(uname)" = "Darwin" ] || die "This is macOS-only. Wine on Linux does not have this problem in the same way."
say "  macOS: yes"

[ -d "$WHISKY_LIB/Wine" ] || die "Whisky is not installed, or not where expected:
  $WHISKY_LIB/Wine

Install Whisky first, from  https://github.com/frankea/Whisky
Then create a bottle and run this again."
say "  Whisky: found"

if pgrep -x Whisky >/dev/null 2>&1 || pgrep -f wineserver >/dev/null 2>&1; then
  die "Whisky or a Windows program is still running. Quit them, then run this again."
fi
say "  Nothing running that would be disturbed: good"

# --- 1. prerequisites -------------------------------------------------------
# These are the tools that do the compiling. They are standard developer tools,
# not anything unusual, and Homebrew is the normal way to get them on a Mac.
step "Checking build tools"

if ! command -v brew >/dev/null 2>&1; then
  say "  Homebrew: MISSING"
  say ""
  say "  Homebrew is the standard package manager for macOS - it installs"
  say "  developer tools. Install it by pasting this into Terminal:"
  say ""
  say '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  say ""
  die "Install Homebrew, then run this script again."
fi
say "  Homebrew: found"

BREW_PREFIX="$(brew --prefix)"
MISSING=""
[ -x "$BREW_PREFIX/opt/bison/bin/bison" ] || MISSING="$MISSING bison"
command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 || MISSING="$MISSING mingw-w64"
[ -d "$BREW_PREFIX/include/freetype2" ] || MISSING="$MISSING freetype"

if [ -n "$MISSING" ]; then
  say "  Missing:$MISSING"
  say ""
  if ask "  Install them now with Homebrew? (a few minutes)"; then
    # shellcheck disable=SC2086
    brew install $MISSING || die "Homebrew could not install:$MISSING"
  else
    say ""
    say "  Install them yourself with:"
    say "    brew install$MISSING"
    die "Prerequisites missing."
  fi
else
  say "  bison, mingw-w64, freetype: all present"
fi

# macOS ships bison 2.3 from 2006 and Wine needs 3.0+. Homebrew keeps its
# modern bison OFF the normal PATH on purpose, so it must be added explicitly.
export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/bin:$PATH"
BISON_V="$(bison --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
[ "${BISON_V%%.*}" -ge 3 ] 2>/dev/null || die "bison is $BISON_V, need 3.0 or newer."
say "  bison in use: $BISON_V"

# --- 2. source --------------------------------------------------------------
step "Getting the source code"
say "  This is CodeWeavers' CrossOver source. It is free software (LGPL),"
say "  published by them because the licence requires it. The mouse fix is"
say "  their work; this script builds it for Whisky."
say ""

if [ -f "$TARBALL" ]; then
  say "  Already downloaded: $(du -h "$TARBALL" | cut -f1)"
else
  say "  Downloading ~142 MB..."
  curl -L --fail --progress-bar -o "$TARBALL" "$TARBALL_URL" \
    || die "Download failed. Check your internet connection and try again."
  say "  Downloaded."
fi

if [ -d "$SRC/sources/wine" ]; then
  say "  Already extracted."
else
  say "  Extracting (takes a minute)..."
  mkdir -p "$SRC"
  tar xzf "$TARBALL" -C "$SRC" sources/wine || die "Could not extract the archive."
  say "  Extracted."
fi

# --- 3. build ---------------------------------------------------------------
step "Building (about 15 minutes)"
say "  Your Mac is now compiling roughly 12,000 source files. This is the"
say "  slow part. You can leave it running and do something else."
say ""
"$HERE/build-engine.sh" || die "The build did not pass its checks. Nothing was installed.
Read the output above - it says which check failed and why."

# --- 4. install -------------------------------------------------------------
step "Installing"
say "  Your original engine will be backed up first."
say ""
"$HERE/install-pointer-fix.sh" install || die "Install refused. Nothing was changed."

# --- done -------------------------------------------------------------------
echo ""
echo "==========================================================="
echo "  Done"
echo "==========================================================="
say ""
say "Start your game as usual and try clicking."
say ""
say "If anything goes wrong, undo it completely with:"
say "    $HERE/install-pointer-fix.sh uninstall"
say ""
say "One more thing worth knowing: Whisky sometimes overwrites part of the"
say "graphics setup when it launches a game, which causes a crash at startup"
say "that looks unrelated. If that happens, see the README section"
say "\"The game crashes when it starts\"."
say ""
