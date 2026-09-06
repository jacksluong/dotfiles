# dotfiles

My macOS setup, managed with [chezmoi](https://www.chezmoi.io/): shell, git,
keyboard remapping, Claude Code, and app settings.

## Setup

All it takes is one command, which can be run on a brand new Mac with nothing
installed:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply \
  --source="$HOME/Developer/dotfiles" jacksluong/dotfiles
```

chezmoi installs itself, clones this repo to `~/Developer/dotfiles`, then
applies it. With distinction between a personal machine and a work machine,
this will:

- Set up SSH keys for GitHub
- Install Homebrew, its packages, and Mac apps
- Create and populates `~/Developer`
- Install remaining tools (e.g., Claude Code, pnpm)
- Write every managed file
- Set up symlinks for personal AI skills repo
- Set up keyboard remapping (kanata)
- Install Mac apps

## Overview

### Shell

zsh with [oh-my-posh](https://ohmyposh.dev), autosuggestions, and syntax
highlighting. `~/.zshrc` also wires up pyenv, pnpm, and fzf for history search.

Helper functions live in `home/dot_config/zsh/` and are sourced at startup:

| File | What it adds |
|---|---|
| `git.sh` | `commit`, `push`, `switch`, `clone`, `merge`, `stash` and friends, wrapping git with prompts and safe defaults |
| `aliases.sh` | `g`, `sw`, `cl`, `ls` via eza, `rm` via trash, and a `cd` that navigates interactively when called with no arguments |
| `icd.sh` | the interactive `cd` picker |
| `helpers.sh` | shared prompt/validation helpers used by the others |

Machine-specific config that shouldn't be synced goes in `~/.zshrc.local`,
which `.zshrc` sources if present. It stays untracked.

### Git and SSH

`~/.config/git/config` is templated per machine. Personal machines commit
with the personal email. Work machines use the work email, plus routing for
repos under the personal GitHub account so they keep canonical remote URLs
but authenticate and commit as personal.

SSH keys are generated on first apply (one key on personal machines, a work
key plus a personal key on work machines) and added to GitHub via `gh`.
`~/.ssh/config` is templated to match.

### Repos

On personal machines, my repos are cloned into `~/Developer`. This directory
is where I keep all my active personal projects and code.

### Keyboard

[kanata](https://github.com/jtroo/kanata) remaps the built-in MacBook
keyboard to a Canary layout with home-row mods and multiple layers. The config
is `home/dot_config/kanata/kanata.kbd`.

[kanata-tray](https://github.com/rszyma/kanata-tray) runs it in the menu bar,
with it automatically started on login. Setup installs the sudoers rule it
needs, but the Input Monitoring and Accessibility permissions must be granted
by hand.

### Claude Code

Multiple files are written to `~/.claude/`:

- `CLAUDE.md` - global instructions applied in every project
- `settings.json` - model, effort, theme, output style, and status line wiring
- `output-styles/custom-concise.md` - the custom output style for Claude Code
- `statusline-command.sh` - custom status line showing model, context use,
  rate limits, and diff size

Setup also installs the `playwright-cli` agent skill at
`~/.claude/skills/playwright-cli`, which is not tracked here.

### AI skills

Personal agent skills live in their own repo,
[jacksluong/skills](https://github.com/jacksluong/skills). It is declared as a
chezmoi external, so chezmoi clones it itself and pulls it whenever chezmoi is
applied.

Symlinks are created for each `skills/<name>/` from the clone into the
directories the harnesses read:

- `~/.claude/skills` for Claude Code
- `~/.agents/skills` for Codex

Edit a skill in `~/Developer/skills` and the change is live in the next agent
session; commit and push to share it with the other machines.

### Editor

The settings and keybindings for my code editor,[Zed](https://zed.dev), are
also synced via `chezmoi`.

- `settings.json` - theme, fonts, agent panel, git, and terminal settings
- `keymap.json` - custom bindings on top of the VSCode base keymap

Zed rewrites both files when settings change in the UI, so `chezmoi re-add`
pulls those changes back into the repo.

### Packages

`Brewfile` installs on every machine: CLI tools (`git`, `fd`, `ripgrep`,
`bat`, `eza`, `fzf`, `jq`, `gh`, `pyenv`, `kanata`, `chezmoi`), zsh plugins,
Raycast, and the Fira Code Nerd Font. `Brewfile.personal` adds Mac apps
(iTerm2, Craft, Zed, Spotify, Steam, Spark, CleanShot) on personal
machines only.

However, this only installs missing packages. Upgrading them requires
manually running `brew upgrade`.

### App settings

Some apps have no non-interactive import, so their settings exports live in
`imports/` and are applied by hand:

- `imports/settings.itermexport` - iTerm2 profiles, keys, and the rest of
  its settings, via Settings > General > Settings > Import All Settings and
  Data
- `imports/raycast.rayconfig` - Raycast settings, via Raycast > Settings >
  Advanced > Import Settings

Also managed are `~/.vimrc` (bootstraps vim-plug), `~/.config/git/ignore`,
`~/.hushlogin`, and the oh-my-posh theme.

## Making changes

```sh
chezmoi diff     # preview
chezmoi apply    # sync repo to $HOME
chezmoi re-add   # pull edits made in $HOME back into the repo
chezmoi update   # pull this repo and the skills repo, then apply
```

Edit files in this repo, or edit the deployed file and re-add it. Setup
scripts are idempotent.
