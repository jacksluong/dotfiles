#!/bin/bash
#
# Pre-installs vim-plug plugins so the first vim launch is instant.
# Runs after apply so ~/.vimrc is in place.
set -euo pipefail

echo "==> Installing vim plugins"
vim +PlugInstall +qall </dev/null >/dev/null 2>&1 || true
