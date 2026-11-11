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

# Barnata, from the DMG of the latest GitHub release. The app updates itself.
if [[ ! -d /Applications/Barnata.app ]]; then
  echo "==> Installing Barnata"
  barnata_latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/jacksluong/barnata/releases/latest)"
  barnata_version="${barnata_latest##*/v}"
  barnata_tmp="$(mktemp -d)"
  curl -fsSL -o "$barnata_tmp/Barnata.dmg" \
    "https://github.com/jacksluong/barnata/releases/download/v$barnata_version/Barnata-$barnata_version.dmg"
  hdiutil attach "$barnata_tmp/Barnata.dmg" -nobrowse -readonly -quiet -mountpoint "$barnata_tmp/mnt"
  ditto "$barnata_tmp/mnt/Barnata.app" /Applications/Barnata.app \
    || { hdiutil detach "$barnata_tmp/mnt" -quiet; rm -rf /Applications/Barnata.app; exit 1; }
  hdiutil detach "$barnata_tmp/mnt" -quiet
  rm -rf "$barnata_tmp"
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

# Node.js, the latest version, set globally through pnpm unless a node is
# already on PATH. pnpm ships without one, and playwright-cli needs it.
if ! command -v node &>/dev/null; then
  echo "==> Installing the latest Node.js with pnpm"
  pnpm runtime set node latest -g
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
