#!/bin/bash
# Quick health check before a gaming session.
#
# On a Mac the CPU and GPU share one pool of memory. When that pool runs out,
# macOS moves memory to the SSD ("swap"), and reading it back causes freezes -
# in BOTH the picture and the sound. That symptom is very often mistaken for
# a graphics problem, and no graphics setting will fix it.

echo "==================================================="
echo "  Pre-game check"
echo "==================================================="
echo ""

PAGE=$(pagesize)
FREE=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
WIRED=$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')
FREE_MB=$(( FREE * PAGE / 1048576 ))
WIRED_GB=$(echo "$WIRED $PAGE" | awk '{printf "%.2f", $1*$2/1073741824}')
SWAP=$(sysctl -n vm.swapusage | sed 's/.*used = \([0-9.]*\)M.*/\1/')
SWAP_INT=${SWAP%.*}

echo "  Free memory : ${FREE_MB} MB"
echo "  Wired memory: ${WIRED_GB} GB   (kernel + GPU; only a reboot frees this)"
echo "  Swap in use : ${SWAP} MB"
echo ""

VERDICT="GOOD - go play"
if [ "${SWAP_INT:-0}" -gt 2000 ]; then
  echo "  >> SWAP IS HIGH. This causes stutter AND crackly audio."
  echo "     REBOOT - swap does not shrink on its own, even after quitting apps."
  VERDICT="REBOOT FIRST"
elif [ "${SWAP_INT:-0}" -gt 500 ]; then
  echo "  >> Some swap in use. Close heavy apps before playing."
  VERDICT="CLOSE SOME APPS"
fi

echo ""
echo "  Biggest memory users right now:"
ps -A -o rss,comm -m 2>/dev/null | awk 'NR>1 && NR<9 {
  n=$0; sub(/^[ ]*[0-9]+[ ]+/,"",n);
  split(n,p,"/"); short=p[length(p)];
  printf "    %6.0f MB  %s\n", $1/1024, substr(short,1,42) }'

echo ""
echo "==================================================="
echo "  Verdict: $VERDICT"
echo "==================================================="
echo ""
echo "Rules of thumb:"
echo "  - Reboot before a long session."
echo "  - Close your web browser. It is usually 1-2 GB on its own."
echo "  - Stutter WITH crackly audio = memory, not graphics."
echo "  - Evenly low FPS with clean audio = graphics settings."
echo ""
echo "Press any key to close."
read -n 1
