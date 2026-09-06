#!/bin/bash
#
# Installs Homebrew if missing
set -euo pipefail

if ! command -v brew &>/dev/null && [[ ! -x /opt/homebrew/bin/brew ]]; then
  echo "==> Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
