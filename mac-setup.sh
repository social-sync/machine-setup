#!/usr/bin/env bash
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

# ─── 3. Zsh & Oh My Zsh ─────────────────────────────────────────────────────

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

declare -A OMZ_PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

for plugin in "${!OMZ_PLUGINS[@]}"; do
  PLUGIN_DIR="$OMZ_CUSTOM/plugins/$plugin"
  if [[ -d "$PLUGIN_DIR" ]]; then
    success "Oh My Zsh plugin '$plugin' already installed."
    (cd "$PLUGIN_DIR" && git pull --quiet 2>/dev/null) || true
  else
    info "Installing Oh My Zsh plugin '$plugin'…"
    git clone --quiet "${OMZ_PLUGINS[$plugin]}" "$PLUGIN_DIR"
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

# ─── 5. Docker Desktop ─────────────────────────────────────────────────────

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

# ─── 6. NVM & Node.js ──────────────────────────────────────────────────────

section "NVM & Node.js"

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

# ─── 7. Python
 ──────────────────────────────────────────────────────────────

section "Python"

if brew list python@3 &>/dev/null || brew list python@3.12 &>/dev/null || brew list python@3.13 &>/dev/null; then
  success "Python 3 already installed via Homebrew — $(python3 --version)"
  brew upgrade python@3 2>/dev/null || brew upgrade python3 2>/dev/null || true
else
  info "Installing Python 3 via Homebrew…"
  brew install python@3
  success "Python installed — $(python3 --version)"
fi

# ─── 8. Go ──────────────────────────────────────────────────────────────────

section "Go"

if brew list go &>/dev/null; then
  success "Go already installed via Homebrew — $(go version)"
  brew upgrade go 2>/dev/null || true
else
  info "Installing Go via Homebrew…"
  brew install go
  success "Go installed — $(go version)"
fi

# Ensure GOPATH is set
if ! grep -qF 'GOPATH' "$SHELL_PROFILE" 2>/dev/null; then
  info "Adding GOPATH to $SHELL_PROFILE"
  echo "" >> "$SHELL_PROFILE"
  echo "# Go" >> "$SHELL_PROFILE"
  echo 'export GOPATH="$HOME/go"' >> "$SHELL_PROFILE"
  echo 'export PATH="$GOPATH/bin:$PATH"' >> "$SHELL_PROFILE"
fi

# ─── 9. Shell Aliases ────────────────────────────────────────────────────────

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
echo "  Git:    $(git --version)"
echo "  Node:   $(node --version 2>/dev/null || echo 'open a new shell')"
echo "  npm:    $(npm --version 2>/dev/null || echo 'open a new shell')"
echo "  Python: $(python3 --version 2>/dev/null)"
echo "  Go:     $(go version 2>/dev/null)"
echo "  Docker: $(docker --version 2>/dev/null || echo 'open Docker Desktop to finish setup')"
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
