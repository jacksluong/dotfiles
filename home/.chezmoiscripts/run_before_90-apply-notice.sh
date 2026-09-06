#!/bin/bash
#
# Labels the output of chezmoi's own apply step, which runs after every
# `before` script and before any `after` script
set -euo pipefail

echo "==> Writing managed files and refreshing skills repo"
