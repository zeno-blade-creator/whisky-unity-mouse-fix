#!/bin/bash
# Find the Wine engine and work out what architecture it was built for.
# Sourced by doctor.sh, install-pointer-fix.sh and build-engine.sh - not run directly.
#
# WHY THIS EXISTS
# ---------------
# Every script here used to hardcode two things: that the engine lives under
# com.franke.Whisky, and that its libraries sit in lib/wine/x86_64-unix. Both
# are true today and neither is true forever:
#
#   - Whisky was discontinued in April 2025. The migration target is CrossOver,
#     which keeps its engine somewhere else entirely.
#   - macOS 27 (fall 2026) removes Rosetta 2 on upgrade; macOS 28 (fall 2027)
#     stops running Intel binaries almost completely. Whisky's engine is
#     x86_64-only, so the engine that replaces it will not be. CodeWeavers
#     already ships a CrossOver Preview built natively for ARM64 that uses their
#     own FEX emulator instead of Rosetta, and its libraries live in an
#     aarch64-* directory, not x86_64-*.
#
# A hardcoded path does not fail with "the engine moved" - it fails with "file
# not found" three functions deep, which reads like the patch is broken. So the
# arch and the root are discovered, once, here.
#
# WHAT THIS DOES NOT DO
# ---------------------
# It does not make the patch architecture-independent. win32u.so is a compiled
# library and must match the engine it is loaded into. This only ensures we
# find the right engine and target the right directory - so the patch can
# follow a move to CrossOver instead of being welded to Whisky's layout.
#
# Sets, on success:
#   ENGINE_LIB            .../lib                 (the dir containing wine/)
#   ENGINE_UNIX_DIR       .../lib/wine/<arch>-unix
#   ENGINE_WIN_DIR        .../lib/wine/<arch>-windows
#   ENGINE_ARCH           x86_64 | aarch64 | arm64 - as the engine names it
#   ENGINE_WIN32U         full path to the engine's win32u.so
#   ENGINE_KIND           whisky | crossover | unknown
#   ENGINE_LABEL          human-readable, for reports
# Always sets:
#   HOST_ARCH             arm64 | x86_64 - what this Mac actually is
#   ROSETTA_PRESENT       yes | no
#   ENGINE_NEEDS_ROSETTA  yes | no | unknown
#   ENGINE_FOUND          yes | no

# --- the Mac ----------------------------------------------------------------
HOST_ARCH="$(uname -m)"
if [ -d /Library/Apple/usr/share/rosetta ] || [ -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]; then
  ROSETTA_PRESENT=yes
else
  ROSETTA_PRESENT=no
fi

# --- where an engine can live ------------------------------------------------
# Order matters: the first root that actually contains an engine wins. Whisky
# first because that is what is installed today; CrossOver after it, so this
# keeps working unchanged the day the bottles move.
#
# Both Whisky forks appear here for the same reason doctor.sh lists both when
# hunting bottles - the maintained fork and the archived original that
# `brew install --cask whisky` still installs use different bundle ids.
ENGINE_LIB_CANDIDATES=(
  "$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/lib"
  "$HOME/Library/Containers/com.franke.Whisky/Libraries/Wine/lib"
  "$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib"
  "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Libraries/Wine/lib"
  "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib"
  "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64"
)

engine_kind_for() {
  case "$1" in
    *CrossOver*)  echo crossover ;;
    *Whisky*)     echo whisky ;;
    *)            echo unknown ;;
  esac
}

ENGINE_FOUND=no
ENGINE_LIB=""
ENGINE_UNIX_DIR=""
ENGINE_WIN_DIR=""
ENGINE_ARCH=""
ENGINE_WIN32U=""
ENGINE_KIND=unknown
ENGINE_LABEL="(none found)"

for cand in "${ENGINE_LIB_CANDIDATES[@]}"; do
  [ -d "$cand/wine" ] || continue
  # Glob the arch dir rather than assuming it. Wine names these <arch>-unix,
  # e.g. x86_64-unix today, aarch64-unix on a native ARM64 build. If a build
  # ever ships more than one, prefer the one matching the host, then fall back
  # to whichever exists - a mismatched arch is still worth reporting, and
  # reporting it clearly is the entire point of this file.
  unixdir=""
  for d in "$cand"/wine/*-unix; do
    [ -d "$d" ] || continue
    a="$(basename "$d")"; a="${a%-unix}"
    if [ "$a" = "$HOST_ARCH" ]; then unixdir="$d"; break; fi
    [ -n "$unixdir" ] || unixdir="$d"
  done
  [ -n "$unixdir" ] || continue

  ENGINE_LIB="$cand"
  ENGINE_UNIX_DIR="$unixdir"
  ENGINE_ARCH="$(basename "$unixdir")"; ENGINE_ARCH="${ENGINE_ARCH%-unix}"
  ENGINE_WIN_DIR="$cand/wine/${ENGINE_ARCH}-windows"
  ENGINE_WIN32U="$unixdir/win32u.so"
  ENGINE_KIND="$(engine_kind_for "$cand")"
  ENGINE_LABEL="${cand/#$HOME/~}"
  ENGINE_FOUND=yes
  break
done

# --- does this engine need Rosetta? -----------------------------------------
# An x86_64 engine on an arm64 Mac runs only through Rosetta. That is the
# combination that stops working in macOS 28, and the one worth naming out loud
# before it turns into an unexplained loader error.
ENGINE_NEEDS_ROSETTA=unknown
if [ "$ENGINE_FOUND" = yes ]; then
  if [ "$ENGINE_ARCH" = "$HOST_ARCH" ]; then
    ENGINE_NEEDS_ROSETTA=no
  else
    case "$ENGINE_ARCH:$HOST_ARCH" in
      x86_64:arm64) ENGINE_NEEDS_ROSETTA=yes ;;
      # aarch64 and arm64 are the same thing under two names - Wine says
      # aarch64, uname says arm64. Not a mismatch.
      aarch64:arm64|arm64:aarch64) ENGINE_NEEDS_ROSETTA=no ;;
      *)            ENGINE_NEEDS_ROSETTA=unknown ;;
    esac
  fi
fi

# Print the architecture picture. Callers decide whether to treat it as fatal;
# doctor.sh only reports, install-pointer-fix.sh refuses to install into an
# engine that cannot run.
engine_report() {
  echo "  host arch      : $HOST_ARCH"
  if [ "$ENGINE_FOUND" != yes ]; then
    echo "  engine         : NOT FOUND"
    echo "                   looked in:"
    for c in "${ENGINE_LIB_CANDIDATES[@]}"; do echo "                     ${c/#$HOME/~}"; done
    return 1
  fi
  echo "  engine         : $ENGINE_KIND  ($ENGINE_LABEL)"
  echo "  engine arch    : $ENGINE_ARCH"
  echo "  rosetta present: $ROSETTA_PRESENT"
  case "$ENGINE_NEEDS_ROSETTA" in
    yes)
      echo "  needs rosetta  : YES - this is an Intel engine on an Apple-silicon Mac"
      if [ "$ROSETTA_PRESENT" = no ]; then
        echo ""
        echo "  *** This engine cannot run. It is built for $ENGINE_ARCH, this Mac is"
        echo "  *** $HOST_ARCH, and Rosetta 2 is not installed to bridge the two."
        echo "  *** macOS 27 removes Rosetta on upgrade (it can be reinstalled);"
        echo "  *** macOS 28 drops it for good. The fix is not this patch - it is"
        echo "  *** an ARM64-native engine. CodeWeavers ship one in CrossOver"
        echo "  *** Preview, built on their FEX emulator rather than Rosetta."
        return 2
      fi
      ;;
    no)      echo "  needs rosetta  : no - engine matches the host" ;;
    unknown) echo "  needs rosetta  : unknown ($ENGINE_ARCH engine on $HOST_ARCH host)" ;;
  esac
  return 0
}
