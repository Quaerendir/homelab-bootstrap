#!/usr/bin/env bash
# ============================================================
#  homelab-bootstrap -- install.sh
#  Modular setup for RHEL / Fedora / Debian / Ubuntu
#
#  Usage: ./install.sh [--all] [--motd] [--zsh] [--ssh] [--sudo] [--thefuck]
#  No args = interactive menu
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="${HOME}"
CURRENT_USER="${USER}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33d'; C='\033[0;36m'; N='\033[0m'
info() { echo -e "\033[0;36m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

detect_pkg_manager() {
  if   command -v dnf &>/dev/null; then PKG="dnf"; DISTRO_FAMILY="rhel"
  elif command -v apt &>/dev/null; then PKG="apt"; DISTRO_FAMILY="debian"
  else die "Unsupported package manager (need dnf or apt)"; fi
  info "Package manager: $PKG / family: $DISTRO_FAMILY"
}

pkg_install() {
  info "Installing packages: $*"
  [ "$PKG" = "dnf" ] && sudo dnf install -y "$@" || sudo apt-get install -y "$@"
}

# ============================================================
# MODULE: motd
# ============================================================
install_motd() {
  info "Installing custom MOTD..."

  if [ "$DISTRO_FAMILY" = "rhel" ]; then
    sudo cp "$SCRIPT_DIR/motd/motd.sh" /etc/profile.d/motd.sh
    sudo chmod +x /etc/profile.d/motd.sh
    [ -f /etc/motd.d/insights-client ] \
      && sudo truncate -s 0 /etc/motd.d/insights-client \
      && warn "Silenced Red Hat Insights MOTD"
    sudo truncate -s 0 /etc/motd 2>/dev/null || true
    ok "MOTD installed -> /etc/profile.d/motd.sh"

  elif [ "$DISTRO_FAMILY" = "debian" ]; then
    sudo mkdir -p /etc/update-motd.d
    sudo cp "$SCRIPT_DIR/motd/motd-debian.sh" /etc/update-motd.d/01-homelab
    sudo chmod +x /etc/update-motd.d/01-homelab
    sudo truncate -s 0 /etc/motd 2>/dev/null || true

    for f in /etc/update-motd.d/10-help-text \
              /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/80-livepatch \
              /etc/update-motd.d/90-updates-available \
              /etc/update-motd.d/91-contract-ua-esm-status; do
      [ -f "$f" ] && sudo chmod -x "$f" && warn "Disabled: $(basename "$f")"
    done

    SSHD_CFG="/etc/ssh/sshd_config"
    SSHD_DROP=""
    if grep -qri "^UsePAM" /etc/ssh/sshd_config.d/ 2>/dev/null; then
      SSHD_DROP=$(grep -rli "^UsePAM" /etc/ssh/sshd_config.d/ | head -n1)
    fi

    fix_usepam() {
      local file="$1"
      if grep -qi "^UsePAM[[:space:]]*no" "$file"; then
        sudo sed -i 's/^UsePAM[[:space:]]*no/UsePAM yes/' "$file"
        warn "Fixed: UsePAM no -> yes in $file"
      elif ! grep -qi "^UsePAM" "$file"; then
        echo "UsePAM yes" | sudo tee -a "$file" > /dev/null
        warn "Added: UsePAM yes to $file"
      fi
    }

    if [ -n "$SSHD_DROP" ]; then
      fix_usepam "$SSHD_DROP"
    else
      fix_usepam "$SSHD_CFG"
    fi

    PAM_SSHD="/etc/pam.d/sshd"
    sudo sed -i '/pam_motd/d' "$PAM_SSHD"

    if grep -q "@include common-session" "$PAM_SSHD"; then
      sudo sed -i '/@include common-session/a session    optional     pam_motd.so\nsession    optional     pam_motd.so motd=/run/motd.dynamic noupdate' "$PAM_SSHD"
    else
      printf '\nsession    optional     pam_motd.so\nsession    optional     pam_motd.so motd=/run/motd.dynamic noupdate\n' | sudo tee -a "$PAM_SSHD" > /dev/null
    fi

    ok "Fixed pam.d/sshd -> pam_motd configured"

    sudo sshd -t && sudo systemctl restart sshd \
      && ok "sshd restarted" \
      || die "sshd config invalid after changes!"

    ok "MOTD installed -> /etc/update-motd.d/01-homelab"
    warn "Log in via a NEW SSH session to see the MOTD"
  fi
}

# ============================================================
# MODULE: zsh
# ============================================================
install_zsh() {
  info "Installing zsh + Oh My Zsh..."
  pkg_install zsh git curl

  if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    warn "Oh My Zsh already installed, skipping."
  fi

  ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}"
  declare -A PLUGINS=(
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
    ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search"
  )
  for name in "${!PLUGINS[@]}"; do
    target="$ZSH_CUSTOM/plugins/$name"
    if [ ! -d "$target" ]; then
      git clone "${PLUGINS[$name]}" "$target" && ok "Plugin cloned: $name"
    else
      warn "Plugin already exists: $name (skipping)"
    fi
  done

  if [ -f "$USER_HOME/.zshrc" ]; then
    backup="$USER_HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp "$USER_HOME/.zshrc" "$backup"
    warn "Backed up existing .zshrc -> $backup"
  fi
  cp "$SCRIPT_DIR/zsh/zshrc" "$USER_HOME/.zshrc"
  ok ".zshrc deployed"

  ZSH_PATH=$(which zsh)
  if [ "$SHELL" != "$ZSH_PATH" ]; then
    chsh -s "$ZSH_PATH" "$CURRENT_USER" \
      && ok "Default shell set to zsh" \
      || warn "chsh failed -- set manually: chsh -s $ZSH_PATH"
  fi
  ok "zsh + Oh My Zsh fully configured"
}

# ============================================================
# MODULE: thefuck
# ============================================================
install_thefuck() {
  info "Installing thefuck via pipx..."
  command -v pipx &>/dev/null || pkg_install pipx

  if command -v thefuck &>/dev/null; then
    warn "thefuck already installed, skipping."; return
  fi

  if command -v python3.11 &>/dev/null; then
    pipx install --python python3.11 thefuck && ok "thefuck installed (python3.11)"
  elif pipx install --fetch-missing-python --python 3.11 thefuck 2>/dev/null; then
    ok "thefuck installed (pipx fetched python3.11)"
  else
    warn "python3.11 not found -- trying system Python (may fail on 3.12+)"
    if [ "$DISTRO_FAMILY" = "rhel" ]; then
      warn "Try: dnf install python3.11 && ./install.sh --thefuck"
    else
      warn "Try: apt install python3.11 && ./install.sh --thefuck"
    fi
    pipx install thefuck || die "thefuck install failed."
  fi
  pipx ensurepath
  ok "thefuck ready"
}

# ============================================================
# MODULE: ssh
# ============================================================
install_ssh() {
  info "Deploying sshd hardening config..."
  SSHD_D="/etc/ssh/sshd_config.d"
  if [ -d "$SSHD_D" ]; then
    sudo cp "$SCRIPT_DIR/ssh/sshd_hardening.conf" "$SSHD_D/99-hardening.conf"
    sudo chmod 600 "$SSHD_D/99-hardening.conf"
    ok "Deployed -> $SSHD_D/99-hardening.conf"
  else
    warn "/etc/ssh/sshd_config.d not found -- appending to /etc/ssh/sshd_config"
    echo "" | sudo tee -a /etc/ssh/sshd_config
    sudo tee -a /etc/ssh/sshd_config < "$SCRIPT_DIR/ssh/sshd_hardening.conf"
  fi
  sudo sshd -t && sudo systemctl restart sshd \
    && ok "sshd hardened and restarted" \
    || die "sshd config validation failed! Fix before restarting."
}

# ============================================================
# MODULE: sudo
# ============================================================
install_sudo() {
  info "Deploying sudoers drop-in..."
  TARGET="/etc/sudoers.d/10-wheel-hardening"
  sudo cp "$SCRIPT_DIR/sudo/10-marek-hardening" "$TARGET"
  sudo chmod 440 "$TARGET"
  [ -f /etc/sudoers.d/90-cloud-init-users ] \
    && sudo rm /etc/sudoers.d/90-cloud-init-users \
    && warn "Removed /etc/sudoers.d/90-cloud-init-users (cloud-init NOPASSWD)"
  sudo visudo -cf "$TARGET" \
    && ok "sudoers drop-in deployed: $TARGET" \
    || die "sudoers syntax error! Check $TARGET"
}

# ============================================================
# Helpers
# ============================================================
usage() {
  cat <<EOF

  homelab-bootstrap

  Usage: $0 [options]
  No options = interactive menu

  --all       Run all modules
  --motd      Custom MOTD (distro-aware: profile.d vs update-motd.d)
  --zsh       zsh + Oh My Zsh + plugins + .zshrc
  --thefuck   thefuck via pipx (python3.11)
  --ssh       sshd hardening drop-in
  --sudo      sudoers hardening (removes NOPASSWD)
  --help      This message

EOF
}

interactive_menu() {
  echo ""
  echo "  homelab-bootstrap -- select modules:"
  echo ""
  declare -A SEL
  for item in \
    "motd:MOTD          -> distro-aware (profile.d / update-motd.d)" \
    "zsh:zsh            -> Oh My Zsh + plugins + .zshrc" \
    "thefuck:thefuck       -> pipx + python3.11" \
    "ssh:ssh hardening  -> sshd_config.d/99-hardening.conf" \
    "sudo:sudo hardening -> removes cloud-init NOPASSWD"
  do
    key="${item%%:*}"; label="${item#*:}"
    read -rp "  Install $label? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] && SEL["$key"]="1"
  done
  echo ""
  for mod in "${!SEL[@]}"; do "install_${mod}"; done
}

# ============================================================
# Main
# ============================================================
detect_pkg_manager

if [ $# -eq 0 ]; then
  interactive_menu
  echo -e "\nDone.\n"
  exit 0
fi

DO_ALL=0
for arg in "$@"; do
  case "$arg" in
    --all)     DO_ALL=1 ;;
    --motd)    install_motd ;;
    --zsh)     install_zsh ;;
    --thefuck) install_thefuck ;;
    --ssh)     install_ssh ;;
    --sudo)    install_sudo ;;
    --help|-h) usage; exit 0 ;;
    *) warn "Unknown: $arg"; usage; exit 1 ;;
  esac
done

[ "$DO_ALL" -eq 1 ] && install_motd && install_zsh && install_thefuck && install_ssh && install_sudo

echo -e "\nDone.\n"
