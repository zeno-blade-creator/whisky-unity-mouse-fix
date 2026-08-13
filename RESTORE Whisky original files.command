#!/bin/bash
# Puts Whisky's original, unmodified Wine files back.
#
# WHEN TO USE THIS
#   - PEAK or Steam starts crashing after the patch
#   - Whisky itself misbehaves
#   - you simply want to undo the change
#
# It restores the three files from the timestamped backup made just before
# the patch was installed. Nothing else is touched: your bottle, your login,
# your games and your settings are all untouched by this.
#
# It is always safe to run. If no backup exists it says so and does nothing.

set -u
WINE_LIB="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/lib/wine"
BACKUP_ROOT="$HOME/Desktop/Wine Windows Games/wine-patch/backups"

echo "==================================================="
echo "  Restore Whisky's original Wine files"
echo "==================================================="
echo ""

if [ ! -d "$BACKUP_ROOT" ]; then
  echo "No backups folder found at:"
  echo "  $BACKUP_ROOT"
  echo ""
  echo "Nothing to restore - the patch was probably never installed."
  echo "Press any key to close."; read -n 1; exit 0
fi

LATEST="$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | tail -1)"
if [ -z "${LATEST:-}" ]; then
  echo "No backups inside $BACKUP_ROOT. Nothing to restore."
  echo "Press any key to close."; read -n 1; exit 0
fi

echo "Restoring from:"
echo "  $LATEST"
echo ""

# Stop anything using Wine first, or the files will be locked.
echo "Stopping Whisky, Steam and any games..."
pgrep -x Whisky >/dev/null && osascript -e 'tell application "Whisky" to quit' 2>/dev/null
sleep 2
pkill -9 -f "PEAK" 2>/dev/null
pkill -9 -f "steamwebhelper" 2>/dev/null
pkill -9 -f "steamservice" 2>/dev/null
pkill -9 -f 'steam.exe' 2>/dev/null
sleep 2
"$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wineserver" -k 2>/dev/null
sleep 2

RESTORED=0
for rel in x86_64-windows/win32u.dll x86_64-windows/user32.dll x86_64-unix/win32u.so; do
  src="$LATEST/$(basename "$rel")"
  dst="$WINE_LIB/$rel"
  if [ -f "$src" ]; then
    if cp "$src" "$dst" 2>/dev/null; then
      echo "  restored $(basename "$rel")"
      RESTORED=$((RESTORED + 1))
    else
      echo "  FAILED to restore $(basename "$rel")"
    fi
  else
    echo "  no backup for $(basename "$rel")"
  fi
done

echo ""
if [ "$RESTORED" = "3" ]; then
  echo "All three files restored. Whisky is back to how it shipped."
else
  echo "WARNING: only $RESTORED of 3 restored. Tell Claude before using Whisky."
  echo "A partial set of these files can make Wine unstable."
fi
echo ""
echo "Press any key to close."
read -n 1
