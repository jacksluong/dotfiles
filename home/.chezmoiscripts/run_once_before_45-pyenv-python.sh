#!/bin/bash
#
# Installs the latest Python with pyenv and makes it the global version, unless
# the global version is already an installed pyenv version.
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv)"

command -v pyenv &>/dev/null || exit 0

global="$(pyenv global | head -n 1)"
if [[ "$global" == system ]] || ! pyenv prefix "$global" &>/dev/null; then
  latest="$(pyenv latest -k 3)"
  echo "==> Installing Python $latest with pyenv"
  pyenv install -s "$latest"
  pyenv global "$latest"
fi
