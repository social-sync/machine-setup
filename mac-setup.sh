#!/bin/bash
#
# mac-setup.sh — Idempotent developer workstation bootstrap for macOS.
#
# Usage:
#   chmod +x mac-setup.sh
#   ./mac-setup.sh
#
# Safe to re-run at any time. It will skip anything already installed and
# upgrade what it can.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │  TABLE OF CONTENTS                                                      │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                          │
# │  Section 1 — Xcode Command Line Tools                                   │
# │    Prerequisite for Homebrew and most dev tools. Detected via            │
# │    xcode-select; waits for the async macOS GUI installer if triggered.   │
# │                                                                          │
# │  Section 2 — Homebrew                                                    │
# │    macOS package manager. Handles Apple Silicon (/opt/homebrew) and      │
# │    Intel (/usr/local) paths. Adds shellenv to the user's profile.        │
# │                                                                          │
# │  Section 3 — Zsh & Oh My Zsh                                            │
# │    Installs latest Zsh via Homebrew and sets it as the default shell.    │
# │    Installs Oh My Zsh framework plus community plugins:                  │
# │      • zsh-autosuggestions                                               │
# │      • zsh-syntax-highlighting                                           │
# │                                                                          │
# │  Section 4 — Git                                                         │
# │    Latest Git via Homebrew (replaces Apple's bundled version).           │
# │    Prints post-install instructions for configuring user.name,           │
# │    user.email, and recommended global defaults.                          │
# │                                                                          │
# │  Section 5 — Visual Studio Code                                          │
# │    Installs VS Code via Homebrew cask. The cask is officially            │
# │    maintained by Microsoft and VS Code auto-updates itself after install.│
# │                                                                          │
# │  Section 6 — Docker Desktop                                              │
# │    Downloads the official .dmg directly from Docker (not Homebrew        │
# │    cask, which tends to lag). Auto-detects arm64 vs amd64.               │
# │                                                                          │
# │  Section 7 — NVM, Node.js & pnpm                                        │
# │    Installs NVM from the official install script, then installs the      │
# │    latest LTS release of Node.js, sets it as default, and installs       │
# │    pnpm globally as the package manager.                                 │
# │                                                                          │
# │  Section 8 — Claude Code                                                 │
# │    Installs the Claude Code CLI for agentic coding from the terminal.    │
# │                                                                          │
# │  Section 9 — 1Password CLI                                              │
# │    Installs the 1Password CLI (op) via the official Homebrew cask.       │
# │    Provides secret management and SSH agent integration.                 │
# │                                                                          │
# │  Section 10 — Shell Aliases                                              │
# │    Writes a managed block of team aliases into ~/.zshrc.                 │
# │    Current aliases: sail, art, pest (Laravel / PHP tooling).             │
# │                                                                          │
# │  Summary — Prints installed versions and Git configuration guide.        │
# │                                                                          │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │  INSTRUCTIONS FOR CLAUDE (AI assistant) — How to maintain this script   │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                          │
# │  This script is designed to be idempotent and extensible. Follow these   │
# │  rules when making changes:                                              │
# │                                                                          │
# │  ADDING A NEW TOOL (Homebrew-based):                                     │
# │    1. Add a new numbered section following the existing pattern:         │
# │       - Use `section "Tool Name"` for the header.                        │
# │       - Check if already installed: `if brew list <pkg> &>/dev/null`.    │
# │       - Install if missing, upgrade if present.                          │
# │    2. Increment subsequent section numbers.                              │
# │    3. Update this table of contents.                                     │
# │    4. Add the tool's version to the Summary section's version printout.  │
# │                                                                          │
# │  ADDING A NEW TOOL (non-Homebrew / custom installer):                    │
# │    1. Follow the same section pattern.                                   │
# │    2. Use `command -v <binary>` or check a known install path to         │
# │       determine if it's already installed.                               │
# │    3. On re-run, update in place (e.g. re-run installer, git pull).     │
# │    4. If PATH or env vars are needed, add them to $SHELL_PROFILE         │
# │       guarded by `if ! grep -qF '<marker>' ...` to avoid duplicates.    │
# │                                                                          │
# │  ADDING A NEW ALIAS:                                                     │
# │    1. Append to the ALIASES array in Section 10. That's it — the         │
# │       managed block pattern handles idempotent replacement.              │
# │                                                                          │
# │  ADDING AN OH MY ZSH PLUGIN:                                            │
# │    1. Add an entry to the OMZ_PLUGIN_NAMES and OMZ_PLUGIN_URLS          │
# │       parallel arrays in Section 3.                                      │
# │    2. Remind the user to enable it in the plugins=() line of .zshrc.    │
# │                                                                          │
# │  GENERAL RULES:                                                          │
# │    • Every section MUST be safe to run repeatedly with no side effects.  │
# │    • Never blindly append to files — always grep for a marker first.     │
# │    • Use `set -euo pipefail` (already set) — handle expected failures    │
# │      with `|| true` or explicit checks.                                  │
# │    • Support both Apple Silicon (arm64) and Intel (x86_64) Macs.        │
# │    • Keep the section numbering and table of contents in sync.           │
# │    • Prefer `brew install` for tools that have a formula — it makes      │
# │      upgrades trivial on re-run.                                         │
# │    • For tools where Homebrew lags significantly behind (e.g. Docker),   │
# │      download the official installer directly.                           │
# │    • When renumbering sections, keep comment headers on a SINGLE LINE.   │
# │      Do NOT split the trailing dashes onto a separate line.              │
# │                                                                          │
# └──────────────────────────────────────────────────────────────────────────┘
#
set -euo pipefail

# ─── Helpers ────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*"; }

section() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  $*${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Ensure we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  err "This script is intended for macOS only."
  exit 1
fi

ARCH="$(uname -m)"  # arm64 or x86_64

# ─── Sudo Pre-flight ───────────────────────────────────────────────────────
# Several steps (Homebrew install, changing default shell, /etc/shells) need
# sudo. We prompt once up front so the script isn't interrupted mid-way.

info "This script requires administrator privileges for some steps."
info "You may be prompted for your password."

if ! sudo -v 2>/dev/null; then
  err "Could not obtain sudo access. Please ensure this user is an Administrator."
  err "You can check in System Settings → Users & Groups."
  exit 1
fi

# Keep sudo alive in the background for the duration of the script
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# ─── 1. Xcode Command Line Tools ───────────────────────────────────────────

section "Xcode Command Line Tools"

if xcode-select -p &>/dev/null; then
  success "Xcode CLT already installed at $(xcode-select -p)"
else
  info "Installing Xcode Command Line Tools (a dialog may appear)…"
  xcode-select --install 2>/dev/null || true

  # Wait until the tools are installed (the GUI installer runs async)
  echo "Waiting for Xcode CLT installation to complete…"
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  success "Xcode CLT installed."
fi

# ─── 2. Homebrew ────────────────────────────────────────────────────────────

section "Homebrew"

if command -v brew &>/dev/null; then
  success "Homebrew already installed — $(brew --version | head -1)"
  info "Running brew update…"
  brew update
else
  info "Installing Homebrew…"
  # Refresh sudo credential immediately before install — Homebrew uses
  # `sudo -n` (non-interactive) when NONINTERACTIVE is set, which will
  # fail if the cached timestamp has expired.
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Make brew available in the current session
  if [[ "$ARCH" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew installed."
fi

# Ensure brew is on PATH for both Intel and Apple Silicon in shell profiles
SHELL_PROFILE=""
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
  SHELL_PROFILE="$HOME/.zprofile"
elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
  SHELL_PROFILE="$HOME/.bash_profile"
fi

if [[ -n "$SHELL_PROFILE" ]]; then
  BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null'
  if ! grep -qF 'brew shellenv' "$SHELL_PROFILE" 2>/dev/null; then
    info "Adding Homebrew to PATH in $SHELL_PROFILE"
    echo "" >> "$SHELL_PROFILE"
    echo "# Homebrew" >> "$SHELL_PROFILE"
    echo "$BREW_SHELLENV" >> "$SHELL_PROFILE"
  fi
fi

# ─── 3. Zsh & Oh My Zsh ────────────────────────────────────────────────────

section "Zsh & Oh My Zsh"

# macOS Catalina+ ships with zsh as default, but ensure it's up to date via Homebrew
if brew list zsh &>/dev/null; then
  success "Zsh already installed via Homebrew — $(zsh --version)"
  brew upgrade zsh 2>/dev/null || true
else
  info "Installing latest Zsh via Homebrew…"
  brew install zsh
  success "Zsh installed — $(zsh --version)"
fi

# Add Homebrew zsh to allowed shells if not already there
BREW_ZSH="$(brew --prefix)/bin/zsh"
if ! grep -qF "$BREW_ZSH" /etc/shells 2>/dev/null; then
  info "Adding $BREW_ZSH to /etc/shells (may require sudo)…"
  echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
fi

# Set Homebrew zsh as default shell if it isn't already
if [[ "$SHELL" != "$BREW_ZSH" ]]; then
  info "Setting Homebrew Zsh as default shell (may require sudo)…"
  chsh -s "$BREW_ZSH" 2>/dev/null || warn "Could not change default shell. Run manually: chsh -s $BREW_ZSH"
else
  success "Default shell is already Homebrew Zsh."
fi

# Oh My Zsh
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  success "Oh My Zsh already installed."
  info "Updating Oh My Zsh…"
  (cd "$HOME/.oh-my-zsh" && git pull --quiet 2>/dev/null) || warn "Oh My Zsh update failed — not critical."
else
  info "Installing Oh My Zsh…"
  # RUNZSH=no  — don't launch a new zsh session after install
  # KEEP_ZSHRC=yes — don't overwrite an existing .zshrc
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "Oh My Zsh installed."
fi

# Install popular plugins if not already present
OMZ_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

OMZ_PLUGIN_NAMES=( "zsh-autosuggestions"  "zsh-syntax-highlighting" )
OMZ_PLUGIN_URLS=(
  "https://github.com/zsh-users/zsh-autosuggestions.git"
  "https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

for i in "${!OMZ_PLUGIN_NAMES[@]}"; do
  plugin="${OMZ_PLUGIN_NAMES[$i]}"
  url="${OMZ_PLUGIN_URLS[$i]}"
  PLUGIN_DIR="$OMZ_CUSTOM/plugins/$plugin"
  if [[ -d "$PLUGIN_DIR" ]]; then
    success "Oh My Zsh plugin '$plugin' already installed."
    (cd "$PLUGIN_DIR" && git pull --quiet 2>/dev/null) || true
  else
    info "Installing Oh My Zsh plugin '$plugin'…"
    git clone --quiet "$url" "$PLUGIN_DIR"
    success "Plugin '$plugin' installed."
  fi
done

# Remind user to enable plugins in .zshrc
cat << 'PLUGINEOF'

  NOTE: To activate the plugins, edit your ~/.zshrc and update the
  plugins line to include them, for example:

    plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

PLUGINEOF

# ─── 4. Git ─────────────────────────────────────────────────────────────────

section "Git"

# Install the latest Git via Homebrew (macOS ships an older version)
if brew list git &>/dev/null; then
  success "Git already installed via Homebrew — $(git --version)"
  brew upgrade git 2>/dev/null || true
else
  info "Installing Git via Homebrew…"
  brew install git
  success "Git installed — $(git --version)"
fi

# ─── 5. Visual Studio Code ─────────────────────────────────────────────────

section "Visual Studio Code"

if brew list --cask visual-studio-code &>/dev/null || [[ -d "/Applications/Visual Studio Code.app" ]]; then
  success "Visual Studio Code already installed."
  brew upgrade --cask visual-studio-code 2>/dev/null || true
else
  info "Installing Visual Studio Code…"
  brew install --cask visual-studio-code
  success "Visual Studio Code installed."
fi

# Add 'code' command to PATH if not already available
if ! command -v code &>/dev/null; then
  info "Linking 'code' command to PATH…"
  VSCODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  if [[ -d "$VSCODE_BIN" ]] && ! grep -qF 'Visual Studio Code' "$SHELL_PROFILE" 2>/dev/null; then
    echo "" >> "$SHELL_PROFILE"
    echo '# VS Code' >> "$SHELL_PROFILE"
    echo "export PATH=\"\$PATH:$VSCODE_BIN\"" >> "$SHELL_PROFILE"
  fi
fi

# ─── 6. Docker Desktop ─────────────────────────────────────────────────────

section "Docker Desktop"

if [[ -d "/Applications/Docker.app" ]]; then
  success "Docker Desktop already installed."
  info "To update Docker Desktop, use its built-in updater (Docker menu → Check for Updates)."
else
  info "Downloading Docker Desktop…"

  if [[ "$ARCH" == "arm64" ]]; then
    DOCKER_DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
  else
    DOCKER_DMG_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
  fi

  DOCKER_DMG="/tmp/Docker.dmg"
  curl -fSL -o "$DOCKER_DMG" "$DOCKER_DMG_URL"

  info "Mounting and installing Docker Desktop…"
  hdiutil attach "$DOCKER_DMG" -nobrowse -quiet
  cp -R "/Volumes/Docker/Docker.app" /Applications/ 2>/dev/null || true
  hdiutil detach "/Volumes/Docker" -quiet
  rm -f "$DOCKER_DMG"

  success "Docker Desktop installed."
  info "Please open Docker Desktop from /Applications to complete initial setup."
fi

# ─── 7. NVM, Node.js & pnpm ────────────────────────────────────────────────

section "NVM, Node.js & pnpm"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  success "NVM already installed."
  # shellcheck source=/dev/null
  source "$NVM_DIR/nvm.sh"
  info "Checking for NVM update…"
  # Re-run the installer — it is idempotent and updates in place
  PROFILE=/dev/null bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh)" 2>/dev/null
else
  info "Installing NVM…"
  PROFILE=/dev/null bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh)"
  success "NVM installed."
fi

# Source NVM so we can use it now
# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

# Ensure NVM initialisation is in shell profile
NVM_INIT_BLOCK='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

if [[ -n "$SHELL_PROFILE" ]] && ! grep -qF 'NVM_DIR' "$SHELL_PROFILE" 2>/dev/null; then
  info "Adding NVM initialisation to $SHELL_PROFILE"
  echo "" >> "$SHELL_PROFILE"
  echo "# NVM" >> "$SHELL_PROFILE"
  echo "$NVM_INIT_BLOCK" >> "$SHELL_PROFILE"
fi

# Install latest LTS Node.js
CURRENT_NODE="$(nvm current 2>/dev/null || echo "none")"
LATEST_LTS="$(nvm version-remote --lts 2>/dev/null || echo "unknown")"

if [[ "$CURRENT_NODE" == "$LATEST_LTS" ]]; then
  success "Node.js LTS ($LATEST_LTS) is already the active version."
else
  info "Installing Node.js LTS…"
  nvm install --lts
  nvm alias default 'lts/*'
  success "Node.js $(node --version) installed and set as default."
fi

# pnpm
if command -v pnpm &>/dev/null; then
  success "pnpm already installed — v$(pnpm --version)"
  info "Upgrading pnpm…"
  corepack prepare pnpm@latest --activate 2>/dev/null || npm install -g pnpm@latest
else
  info "Installing pnpm…"
  # Prefer corepack (ships with Node 16.13+), fall back to npm global install
  if command -v corepack &>/dev/null; then
    corepack enable
    corepack prepare pnpm@latest --activate
  else
    npm install -g pnpm
  fi
  success "pnpm installed — v$(pnpm --version)"
fi

# ─── 8. Claude Code ────────────────────────────────────────────────────────

section "Claude Code"

if command -v claude &>/dev/null; then
  success "Claude Code already installed — $(claude --version 2>/dev/null || echo 'installed')"
  info "Re-running installer to check for updates…"
  curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || true
else
  info "Installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash
  success "Claude Code installed."
fi

# ─── 9. 1Password CLI ──────────────────────────────────────────────────────

section "1Password CLI"

# 1Password CLI is distributed via their official Homebrew cask
if command -v op &>/dev/null; then
  success "1Password CLI already installed — $(op --version)"
  brew upgrade --cask 1password-cli 2>/dev/null || true
else
  info "Installing 1Password CLI…"
  brew install --cask 1password-cli
  success "1Password CLI installed — $(op --version)"
fi

cat << 'OPEOF'

  NOTE: To use the 1Password CLI you need to sign in:

    eval $(op signin)

  For SSH agent integration, add the following to ~/.ssh/config:

    Host *
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  This requires the 1Password desktop app with SSH Agent enabled
  under Settings → Developer → SSH Agent.

OPEOF

# ─── 10. Shell Aliases ─────────────────────────────────────────────────────

section "Shell Aliases"

ZSHRC="$HOME/.zshrc"

# Create .zshrc if it doesn't exist
touch "$ZSHRC"

# Define aliases — add new ones here and re-run the script
declare -a ALIASES=(
  "alias sail='./vendor/bin/sail'"
  "alias art='php artisan'"
  "alias pest='./vendor/bin/pest'"
)

ALIAS_MARKER="# ── Team Aliases (managed by mac-setup.sh) ──"
ALIAS_END_MARKER="# ── End Team Aliases ──"

if grep -qF "$ALIAS_MARKER" "$ZSHRC" 2>/dev/null; then
  info "Alias block found in .zshrc — updating…"
  # Remove the old managed block (between markers, inclusive)
  sed -i '' "/$ALIAS_MARKER/,/$ALIAS_END_MARKER/d" "$ZSHRC"
fi

# Write the managed alias block
{
  echo ""
  echo "$ALIAS_MARKER"
  for a in "${ALIASES[@]}"; do
    echo "$a"
  done
  echo "$ALIAS_END_MARKER"
} >> "$ZSHRC"

success "Aliases written to $ZSHRC:"
for a in "${ALIASES[@]}"; do
  echo "    $a"
done

# ─── Summary ────────────────────────────────────────────────────────────────

section "Setup Complete!"

echo ""
echo "Installed versions:"
echo "  Git:        $(git --version)"
echo "  Node:       $(node --version 2>/dev/null || echo 'open a new shell')"
echo "  npm:        $(npm --version 2>/dev/null || echo 'open a new shell')"
echo "  pnpm:       $(pnpm --version 2>/dev/null || echo 'open a new shell')"
echo "  Claude:     $(claude --version 2>/dev/null || echo 'open a new shell')"
echo "  1P CLI:     $(op --version 2>/dev/null || echo 'open a new shell')"
echo "  Docker:     $(docker --version 2>/dev/null || echo 'open Docker Desktop to finish setup')"
echo ""

# ─── Git Configuration Reminder ─────────────────────────────────────────────

cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ACTION REQUIRED — Git Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please run the following commands to configure Git with
your identity (replace with your actual details):

  git config --global user.name "Your Name"
  git config --global user.email "you@company.com"

Recommended defaults (already sensible, but worth setting explicitly):

  # Use 'main' as the default branch name
  git config --global init.defaultBranch main

  # Reconcile divergent branches with rebase on pull
  git config --global pull.rebase true

  # Improve diff readability
  git config --global diff.algorithm histogram

  # Set VS Code as the default editor (optional)
  git config --global core.editor "code --wait"

  # Enable credential caching via macOS Keychain
  git config --global credential.helper osxkeychain

  # Useful aliases
  git config --global alias.st  status
  git config --global alias.co  checkout
  git config --global alias.br  branch
  git config --global alias.lg  "log --oneline --graph --decorate --all"

To verify your config:
  git config --global --list

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo ""
info "Open a new terminal window to pick up all PATH changes."
echo ""
