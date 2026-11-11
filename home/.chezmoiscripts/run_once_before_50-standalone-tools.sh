#!/bin/bash
#
# Installs tools whose docs recommend their own installer over Homebrew.
# Every step is guarded, so re-running is safe.
set -euo pipefail

# Claude Code
if ! command -v claude &>/dev/null && [[ ! -x "$HOME/.local/bin/claude" ]]; then
  echo "==> Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# gcloud (Apple silicon), per https://docs.cloud.google.com/sdk/docs/install-sdk.
# The pyenv shims make the installer use pyenv's Python.
if [[ ! -d "$HOME/google-cloud-sdk" ]]; then
  echo "==> Installing gcloud"
  gcloud_tmp="$(mktemp -d)"
  (
    cd "$gcloud_tmp"
    curl -fsSLO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz
    tar -xf google-cloud-cli-darwin-arm.tar.gz
  )
  mv "$gcloud_tmp/google-cloud-sdk" "$HOME/google-cloud-sdk"
  rm -rf "$gcloud_tmp"
  PATH="$HOME/.pyenv/shims:$PATH" "$HOME/google-cloud-sdk/install.sh" --quiet --install-python false \
    || { rm -rf "$HOME/google-cloud-sdk"; exit 1; }
fi

# playwright-cli comes from pnpm, so put pnpm on PATH before checking for either
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
export PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH"

# pnpm
if ! command -v pnpm &>/dev/null; then
  echo "==> Installing pnpm"
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  hash -r
fi

# playwright-cli
if ! command -v playwright-cli &>/dev/null; then
  echo "==> Installing playwright-cli"
  pnpm add -g @playwright/cli
  hash -r
fi

# playwright-cli skills
if [[ ! -d "$HOME/.claude/skills/playwright-cli" ]]; then
  echo "==> Installing the playwright-cli agent skill"
  playwright-cli install --skills -g
fi

# impeccable
if [[ ! -d "$HOME/.claude/skills/impeccable" ]]; then
  echo "==> Installing the impeccable agent skill"
  pnpm dlx impeccable install
fi
