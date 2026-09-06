#!/bin/bash
#
# Symlinks every skill in the ~/Developer/skills clone into the directories
# Claude Code and Codex read, and drops links to skills that no longer exist.
set -euo pipefail

clone="$HOME/Developer/skills"
repo="$clone/skills"

if [[ ! -d "$repo" ]]; then
  exit 0
fi

# chezmoi clones the external over HTTPS so a keyless first apply works
# but SSH is preferred for pushing
push_url="git@github.com:jacksluong/skills.git"
if [[ "$(git -C "$clone" config --get remote.origin.pushurl 2>/dev/null)" != "$push_url" ]]; then
  git -C "$clone" remote set-url --push origin "$push_url"
  echo "==> Set the skills push URL to $push_url"
fi

for dest in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$dest"

  # Drop any symlinks to skills that no longer exist
  for link in "$dest"/*; do
    [[ -L "$link" ]] || continue
    [[ "$(readlink "$link")" == "$repo"/* ]] || continue
    if [[ ! -e "$link" ]]; then
      rm "$link"
      echo "==> Unlinked $(basename "$link") from $dest"
    fi
  done

  for skill in "$repo"/*/; do
    [[ -f "$skill/SKILL.md" ]] || continue
    name="$(basename "$skill")"
    # Skip real directories
    if [[ -e "$dest/$name" && ! -L "$dest/$name" ]]; then
      echo "==> Skipping $name: $dest/$name exists and is not a symlink" >&2
      continue
    fi
    if [[ "$(readlink "$dest/$name" 2>/dev/null)" != "${skill%/}" ]]; then
      ln -sfn "${skill%/}" "$dest/$name"
      echo "==> Linked $name into $dest"
    fi
  done
done
