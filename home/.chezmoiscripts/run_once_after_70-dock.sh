#!/bin/bash
#
# Replaces the Dock's pinned items with the list below, in order. Runs after
# apply so the apps from the Brewfiles are installed.
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v dockutil &>/dev/null; then
  echo "==> dockutil is not installed, skipping Dock setup" >&2
  exit 0
fi

apps=(
  "/Applications/Spark Desktop.app"
  "/Applications/Craft.app"
  "/System/Applications/Calendar.app"
  "/System/Applications/Messages.app"
  "/System/Applications/Reminders.app"
  "/Applications/Safari.app"
  "/Applications/Zed.app"
  "/Applications/Claude.app"
)

echo "==> Setting up the Dock"

# Every change skips the Dock restart, so the Dock reloads once at the end
dockutil --remove all --no-restart >/dev/null

for app in "${apps[@]}"; do
  if [[ ! -d "$app" ]]; then
    echo "==> $app is not installed, leaving it out of the Dock" >&2
    continue
  fi
  dockutil --add "$app" --section apps --no-restart >/dev/null \
    || echo "==> Could not add $app to the Dock" >&2
done

dockutil --add "$HOME/Downloads" --section others \
  --view fan --display stack --sort dateadded --no-restart >/dev/null \
  || echo "==> Could not add Downloads to the Dock" >&2

killall Dock
