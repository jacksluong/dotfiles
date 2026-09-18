#!/bin/bash
#
# Launches Barnata so the menu bar item is there to finish setup in.
set -euo pipefail

if [[ -d /Applications/Barnata.app ]]; then
  echo "==> Launching Barnata"
  open -a Barnata
else
  echo "barnata-launch: /Applications/Barnata.app is missing, skipping" >&2
fi
