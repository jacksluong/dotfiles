# dotfiles

My macOS setup, managed with [chezmoi](https://www.chezmoi.io/): shell, git,
keyboard remapping, Claude Code, and app settings. I use this primarily for
syncing configurations across machines (e.g., app settings, shell config), but
it also serves to streamline the setup of new machines.

## Setup

All it takes is one command, which can be run on an existing computer or a
brand new Mac with nothing installed:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply \
  --source="$HOME/Developer/dotfiles" jacksluong/dotfiles
```

chezmoi installs itself, clones this repo to `~/Developer/dotfiles`, asks a
few setup questions, then applies it. This will:

- Set up SSH keys for GitHub
- Install Homebrew, its packages, and Mac apps
- Create and populate `~/Developer`
- Install remaining tools (e.g., Claude Code, pnpm)
- Write every managed file
- Set up symlinks for personal AI skills repo
- Set up keyboard remapping (kanata and Barnata)

### Setup questions

| Question | Asked when |
|---|---|
| Will this machine also be used for work? | always |
| App bundles to install: personal, work (each listing its apps) | machine is also for work |
| Work GitHub email, blank if the personal GitHub is used for work | machine is also for work |
| Which identity is the default for Git and GitHub: personal or work? | work email given |
| Work GitHub org, blank if work repos are on a host other than github.com | personal is the default |

A personal-only machine installs the personal bundle and skips all work
setup. Leaving the work email blank skips the work Git and SSH setup.

## Overview

### Shell

zsh with [oh-my-posh](https://ohmyposh.dev) (for that sweet prompt customization),
[autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), and [syntax
highlighting](https://github.com/zsh-users/zsh-syntax-highlighting). `~/.zshrc`
also wires up pyenv, pnpm, fzf for history search, and all of my custom shell
functions, which are described below.

| File | What it adds |
|---|---|
| `git.sh` | `commit`, `push`, `switch`, `clone`, `merge`, `stash` and friends, wrapping git with prompts and safe defaults |
| `aliases.sh` | `g` for `git`, `sw` for git switching, `cl` for claude, `rm` via `trash`, a `cd` that navigates interactively when called with no arguments, etc. |
| `icd.sh` | the interactive `cd` picker (see [gist](https://gist.github.com/jacksluong/744ee3e30f6fc05a5563353e6db28aca)) |
| `helpers.sh` | shared prompt/validation helpers used by the others |

Machine-specific config that shouldn't be synced goes in `~/.zshrc.local`,
which `.zshrc` sources if present. It stays untracked.

### Git and SSH

`~/.config/git/config` is templated per machine. Commits use the default
identity's email. With a work email, the other identity's email applies to:

- work default: repos under my personal GitHub user
- personal default, with a work org: repos under that org
- personal default, no work org: repos with a remote outside github.com

SSH keys are generated on first apply and added to GitHub via `gh`.
`~/.ssh/config` is templated to match.

### Repos

With the personal bundle, my repos are cloned into `~/Developer`. This directory
is where I keep all of my active personal projects and code.

### Keyboard

[kanata](https://github.com/jtroo/kanata) remaps the built-in MacBook
keyboard to a Canary layout with home-row mods and multiple layers using
[my config](https://github.com/jacksluong/dotfiles/blob/main/home/dot_config/kanata/kanata.kbd),
which has full parity with [my split keyboard layout](https://configure.zsa.io/voyager/layouts/JRoWm/latest/0)
for my Voyager).

To enable easier kanata management via a menu bar icon, I use [Barnata](https://github.com/jacksluong/barnata),
an app I created. The config is tracked by chezmoi.

### Claude Code

Multiple files are written to `~/.claude/`:

- `CLAUDE.md` - global instructions applied in every project
- `settings.json` - model, effort, theme, output style, and status line wiring
- `output-styles/custom-concise.md` - the custom output style for Claude Code
- `statusline-command.sh` - custom status line showing model, context use,
  rate limits, and diff size

### AI skills

Personal agent skills live in their own repo,
[jacksluong/skills](https://github.com/jacksluong/skills). It is declared as a
chezmoi external, so chezmoi clones it itself and pulls it whenever chezmoi is
applied.

Symlinks are created for each `skills/<name>/` from the clone into the
directories the harnesses read:

- `~/.claude/skills` for Claude Code
- `~/.agents/skills` for Codex

When a skill is edited in `~/Developer/skills`, the change is live in the next
agent session. I also have the [Impeccable](https://impeccable.style/) and
[Playwright CLI](https://playwright.dev/) skills installed globally, but they
are installed via script and not tracked by `chezmoi`.

### Editor

The settings and keybindings for my code editor, [Zed](https://zed.dev), are
also synced via `chezmoi`.

- `settings.json` - theme, fonts, agent panel, git, and terminal settings
- `keymap.json` - custom bindings on top of the VSCode base keymap

Zed rewrites both files when settings change in the UI, so `chezmoi re-add`
pulls those changes back into the repo.

### Homebrew

`Brewfile` installs on every machine CLI tools (`git`, `bat`, `fzf`, `gh`,
`pyenv`, `kanata`, `chezmoi`, etc.), zsh plugins, a few apps (Barnata,
ClaudeUsageBar, AutoPiP, Raycast, Craft), and the Fira Code Nerd Font (gotta
love ligatures!).

The app bundles chosen during setup add more:

- `Brewfile.personal` - iTerm2, Zed, Spotify, Steam, Spark, CleanShot, Xcode,
  iWork apps, and Safari extensions (uBlock Origin Lite, TabBack, Capital One
  Shopping)
- `Brewfile.work` - Slack, Postman

Mac App Store apps are installed by `brew bundle` through
[mas](https://github.com/mas-cli/mas).

### Configs and app settings

Some apps have no non-interactive import, so their settings exports live in
`imports/` and are applied by hand:

- `imports/iterm/keybindings.itermkeymap` and `imports/iterm/profiles.json` -
  iTerm2 key bindings and profiles
- `imports/raycast/raycast.rayconfig` - Raycast settings, via Raycast >
  Settings > Advanced > Import Settings

`imports/macos/symbolichotkeys.plist` (System Settings > Keyboard > Keyboard
Shortcuts bindings) is imported by a setup script, but the App Shortcuts tab
within that needs me to put in the shortcuts.

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

## How it works

Each `chezmoi apply` then goes through three phases:

1. **`before` scripts.** These scripts live in `home/.chezmoiscripts/` and run
   before the apply itself, in alphabetical order. In this repo, they install
   Homebrew, set up tools that ship their own installer (e.g., Claude Code, pnpm,
   playwright-cli), set up SSH keys, and do other things.
2. **The apply.** I have chezmoi track an external git repo that contains my AI
   skills, so that gets cloned. Then, every managed file is rendered and written
   to its place in `$HOME`. This includes all the files related to shell setup,
   app config (Zed, Claude Code, etc.), and more.
3. **`after` scripts.** More scripts that live in `home/.chezmoiscripts/` but
   run after the apply. Their actions include but are not limited to: install
   vim plugins, clone my repos, and set up my keyboard as described above.

> Note: `home/` is the source directory for `$HOME`, which determines where
  files are written. Nothing outside of `home/` is managed by chezmoi.

There are chezmoi prefixes that have special meanings, such as `private_` and
`dot_`. The name of a script in `home/.chezmoiscripts/` determines when it runs:

| Prefix | When it runs |
|---|---|
| `run_once_` | once per machine, tracked by the script's contents |
| `run_onchange_` | again whenever the script's contents change |
| `run_` | on every apply |

Generally, most of my chezmoi scripts are only involved in setting up a new
machine.
