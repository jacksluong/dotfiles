# Homebrew refuses to load non-official taps until they are trusted
tap "jacksluong/tap", trusted: true
tap "jandedobbeleer/oh-my-posh", trusted: true
tap "artzainnn/tap", trusted: { casks: ["claudeusagebar"] }
tap "vordenken/autopip", "https://github.com/vordenken/AutoPiP", trusted: { casks: ["autopip"] }

# --- Formulae ---
brew "chezmoi"
brew "git"
brew "bash"
brew "fd"
brew "ripgrep"
brew "bat"
brew "eza"
brew "fzf"
brew "jq"
brew "gh"
brew "oh-my-posh"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "pyenv"
brew "pyenv-virtualenv"
brew "kanata"

# --- Casks ---
# Personal-machine-only apps live in Brewfile.personal, installed only when
# the `personal` chezmoi prompt was answered yes
cask "barnata", args: { adopt: true }
cask "claudeusagebar", args: { adopt: true }
cask "autopip", args: { adopt: true }
cask "raycast", args: { adopt: true }
cask "font-fira-code-nerd-font"
