# dotfiles

macOS dotfiles managed with [chezmoi](https://www.chezmoi.io/). See `README.md`
for what's covered.

## Hard rules

- **Never use the `exact_` prefix** on any file or directory name. `exact_`
  makes chezmoi delete unmanaged files in the target directory on apply. On a
  shared target like `~/Library` that destroys user data. Banned repo-wide, no
  exceptions.
- **Never run `chezmoi apply`, `chezmoi update`, `chezmoi init --apply`**, or
  anything else that writes to `$HOME`. `chezmoi diff`, `chezmoi status`, and
  `chezmoi execute-template` are fine.
- Do not run the setup scripts in `home/.chezmoiscripts/` directly.
