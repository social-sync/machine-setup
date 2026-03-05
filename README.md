# machine-setup

Idempotent developer workstation bootstrap for macOS. Safe to re-run at any time — it skips anything already installed and upgrades what it can.

## Quick start

Run this in Terminal to set up a new Mac:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/social-sync/machine-setup/main/mac-setup.sh)"
```

## What it installs

- **Xcode Command Line Tools** — prerequisite for Homebrew and most dev tools
- **Homebrew** — macOS package manager (supports Apple Silicon and Intel)
- **Zsh & Oh My Zsh** — latest Zsh via Homebrew, Oh My Zsh framework, plus plugins:
  - zsh-autosuggestions
  - zsh-syntax-highlighting
- **Git** — latest version via Homebrew
- **Visual Studio Code** — via Homebrew cask, with `code` command linked to PATH
- **NVM, Node.js & pnpm** — NVM from the official installer, latest LTS Node, and pnpm via corepack
- **Claude Code** — CLI for agentic coding from the terminal
- **1Password CLI** — secret management and SSH agent integration
- **MySQL Client 8.4** — command-line client via Homebrew, force-linked to PATH

## Shell aliases

The script adds these aliases to `~/.zshrc` (managed automatically on re-run):

| Alias | Command | Description |
|-------|---------|-------------|
| `sail` | `./vendor/bin/sail` | Laravel Sail |
| `art` | `php artisan` | Laravel Artisan |
| `pest` | `./vendor/bin/pest` | Pest test runner |
| `pintd` | `./vendor/bin/pint --dirty` | Laravel Pint (dirty files only) |

## After running the script

These steps still need to be done manually:

### Git configuration

```sh
git config --global user.name "Your Name"
git config --global user.email "you@company.com"
```

Recommended defaults:

```sh
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global diff.algorithm histogram
git config --global core.editor "code --wait"
git config --global credential.helper osxkeychain
```

### 1Password CLI

Sign in to 1Password CLI:

```sh
eval $(op signin)
```

### Oh My Zsh plugins

Enable the installed plugins by updating the `plugins` line in `~/.zshrc`:

```sh
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
```

### Open a new terminal

Open a new terminal window to pick up all PATH changes.