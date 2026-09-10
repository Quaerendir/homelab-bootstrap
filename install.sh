#!/usr/bin/env bash
# ============================================================
#  homelab-bootstrap -- install.sh
#  Modular setup for RHEL / Fedora / Debian / Ubuntu / FreeBSD / Solaris
#
#  Usage: ./install.sh [--all] [--motd] [--zsh] [--ssh] [--sudo] [--pay-respects]
#  No args = interactive menu
#
#  FreeBSD prereqs (base has no bash/curl/sudo/git):
#    pkg install -y bash curl git sudo
#
#  Solaris 11.4 prereqs (minimal images may lack bash/curl/sudo/git):
#    pkg install shell/bash web/curl developer/versioning/git security/sudo
#  IPS package (FMRI) names below are best-effort -- verify against your
#  publisher/repo if `pkg install` reports "no matching package".
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# $USER / $HOME aren't guaranteed in minimal environments (curl|bash on a fresh
# VM, su without -l, cron, CI). Fall back to passwd db so `set -u` doesn't bite.
CURRENT_USER="${USER:-$(id -un)}"
USER_HOME="${HOME:-$(getent passwd "$CURRENT_USER" 2>/dev/null | cut -d: -f6)}"
USER_HOME="${USER_HOME:-$HOME}"

# Fresh FreeBSD installs run as root without sudo -- make it optional
SUDO="sudo"
[ "$(id -u)" -eq 0 ] && SUDO=""

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33d'; C='\033[0;36m'; N='\033[0m'
info() { echo -e "\033[0;36m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

detect_pkg_manager() {
  if [ "$(uname -s)" = "FreeBSD" ]; then
    PKG="pkg"; DISTRO_FAMILY="freebsd"
    if [ -n "$SUDO" ] && ! command -v sudo &>/dev/null; then
      die "FreeBSD: run as root, or install sudo first: pkg install -y sudo"
    fi
  elif [ "$(uname -s)" = "SunOS" ]; then
    # PKG="ips" (not "pkg") -- Solaris's package command is also literally
    # named `pkg`, but the CLI syntax/exit codes differ from FreeBSD's pkg(8).
    PKG="ips"; DISTRO_FAMILY="solaris"
    if [ -n "$SUDO" ] && ! command -v sudo &>/dev/null; then
      die "Solaris: run as root, or install sudo first: pkg install security/sudo"
    fi
  elif command -v dnf &>/dev/null; then PKG="dnf"; DISTRO_FAMILY="rhel"
  elif command -v apt &>/dev/null; then PKG="apt"; DISTRO_FAMILY="debian"
  else die "Unsupported package manager (need dnf, apt, FreeBSD pkg or Solaris IPS)"; fi
  info "Package manager: $PKG / family: $DISTRO_FAMILY"
}

# Common tool names -> Solaris IPS FMRIs (best-effort, verify on your image)
declare -A SOLARIS_PKG_MAP=(
  [bash]="shell/bash"
  [zsh]="shell/zsh"
  [git]="developer/versioning/git"
  [curl]="web/curl"
  [sudo]="security/sudo"
)

pkg_install() {
  info "Installing packages: $*"
  case "$PKG" in
    dnf) sudo dnf install -y "$@" ;;
    apt) sudo apt-get install -y "$@" ;;
    pkg) $SUDO pkg install -y "$@" ;;
    ips)
      local mapped=() n rc=0
      for n in "$@"; do mapped+=("${SOLARIS_PKG_MAP[$n]:-$n}"); done
      # `rc=$?` after `! cmd` would capture the NEGATED status, not cmd's real
      # exit code -- `cmd || rc=$?` is the idiom that keeps both the real code
      # and set -e's exemption (cmd is not the list's last element).
      $SUDO pkg install -q "${mapped[@]}" || rc=$?
      # exit 4 = "no changes were made" (already installed/up to date)
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
        warn "pkg install failed (exit $rc): ${mapped[*]}"
        return "$rc"
      elif [ "$rc" -eq 4 ]; then
        warn "Already installed: ${mapped[*]}"
      fi
      ;;
  esac
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

  elif [ "$DISTRO_FAMILY" = "freebsd" ]; then
    # No /etc/profile.d or update-motd.d on FreeBSD -- hook login rc files instead
    $SUDO cp "$SCRIPT_DIR/motd/motd-freebsd.sh" /usr/local/etc/homelab-motd.sh
    $SUDO chmod 644 /usr/local/etc/homelab-motd.sh

    HOOK='[ -f /usr/local/etc/homelab-motd.sh ] && . /usr/local/etc/homelab-motd.sh'

    # sh/bash login shells
    if ! grep -qF 'homelab-motd.sh' /etc/profile 2>/dev/null; then
      printf '\n# homelab-bootstrap MOTD\n%s\n' "$HOOK" | $SUDO tee -a /etc/profile > /dev/null
      ok "Hooked -> /etc/profile"
    fi
    # zsh login shells (pkg zsh reads /usr/local/etc/zprofile)
    if ! grep -qF 'homelab-motd.sh' /usr/local/etc/zprofile 2>/dev/null; then
      printf '\n# homelab-bootstrap MOTD\n%s\n' "$HOOK" | $SUDO tee -a /usr/local/etc/zprofile > /dev/null
      ok "Hooked -> /usr/local/etc/zprofile"
    fi

    # Neutralize base MOTD machinery so it doesn't double-print
    $SUDO sysrc update_motd="NO" > /dev/null
    [ -f /etc/motd.template ] && $SUDO truncate -s 0 /etc/motd.template   # 13.0+
    [ -f /etc/motd ]          && $SUDO truncate -s 0 /etc/motd            # 12.x legacy
    [ -f /var/run/motd ]      && $SUDO truncate -s 0 /var/run/motd
    warn "Base MOTD disabled (sysrc update_motd=NO, templates truncated)"

    ok "MOTD installed -> /usr/local/etc/homelab-motd.sh"
    warn "csh/tcsh login shells will NOT source it (POSIX sh / bash / zsh only)"

  elif [ "$DISTRO_FAMILY" = "solaris" ]; then
    # No /etc/profile.d or update-motd.d on Solaris -- hook login rc files instead
    $SUDO cp "$SCRIPT_DIR/motd/motd-solaris.sh" /etc/homelab-motd.sh
    $SUDO chmod 644 /etc/homelab-motd.sh

    HOOK='[ -f /etc/homelab-motd.sh ] && . /etc/homelab-motd.sh'

    # Solaris's native /usr/bin/grep has no -F (and /usr/bin/fgrep has no -q) --
    # plain BRE `grep -q` is the only idempotency check that actually works here.
    # sh/ksh/bash login shells
    if ! grep -q 'homelab-motd.sh' /etc/profile 2>/dev/null; then
      printf '\n# homelab-bootstrap MOTD\n%s\n' "$HOOK" | $SUDO tee -a /etc/profile > /dev/null
      ok "Hooked -> /etc/profile"
    fi
    # zsh login shells (default ZSH_CONFIGDIR is /etc unless the pkg overrides it)
    if ! grep -q 'homelab-motd.sh' /etc/zprofile 2>/dev/null; then
      printf '\n# homelab-bootstrap MOTD\n%s\n' "$HOOK" | $SUDO tee -a /etc/zprofile > /dev/null
      ok "Hooked -> /etc/zprofile"
    fi

    # sshd prints /etc/motd directly (PrintMotd), independent of shell profiles
    [ -f /etc/motd ] && $SUDO truncate -s 0 /etc/motd
    warn "Base /etc/motd truncated to avoid double-printing"

    ok "MOTD installed -> /etc/homelab-motd.sh"
    warn "csh/tcsh login shells will NOT source it (POSIX sh / bash / zsh only)"
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
    if [ "$DISTRO_FAMILY" = "solaris" ]; then
      # Solaris has no chsh(1) -- shell change goes through usermod(8)
      $SUDO usermod -s "$ZSH_PATH" "$CURRENT_USER" \
        && ok "Default shell set to zsh (usermod)" \
        || warn "usermod failed -- set manually: usermod -s $ZSH_PATH $CURRENT_USER"
    else
      chsh -s "$ZSH_PATH" "$CURRENT_USER" \
        && ok "Default shell set to zsh" \
        || warn "chsh failed -- set manually: chsh -s $ZSH_PATH"
    fi
  fi
  ok "zsh + Oh My Zsh fully configured"
}

# ============================================================
# MODULE: pay-respects  (thefuck replacement)
# ============================================================
# thefuck is effectively abandoned upstream and breaks on Python 3.12+
# (distutils removed per PEP 632, no fallback). pay-respects is a Rust
# rewrite: single static binary, sub-ms suggestions, no Python runtime.
# Install order: distro package -> cargo (if a rust toolchain is present)
# -> upstream prebuilt-binary installer.
install_payrespects() {
  if command -v pay-respects &>/dev/null; then
    warn "pay-respects already installed, skipping."; return
  fi

  # cargo helper: core + runtime-rules + request-ai modules
  _cargo_payrespects() {
    cargo install pay-respects \
                  pay-respects-module-runtime-rules \
                  pay-respects-module-request-ai
  }

  if [ "$DISTRO_FAMILY" = "freebsd" ]; then
    info "Installing pay-respects on FreeBSD..."
    # No prebuilt FreeBSD binaries upstream -- pkg if packaged, else cargo.
    if $SUDO pkg install -y pay-respects 2>/dev/null; then
      ok "pay-respects installed via pkg"; return
    fi
    if command -v cargo &>/dev/null; then
      if _cargo_payrespects; then ok "pay-respects installed via cargo"; return; fi
      warn "cargo install failed."
    fi
    warn "No pay-respects pkg and no rust toolchain."
    warn "Install rust then re-run:  pkg install -y rust && ./install.sh --pay-respects"
    return
  fi

  if [ "$DISTRO_FAMILY" = "solaris" ]; then
    info "Installing pay-respects on Solaris..."
    # No IPS package upstream and no prebuilt Solaris/illumos binary -- cargo only.
    if command -v cargo &>/dev/null; then
      if _cargo_payrespects; then ok "pay-respects installed via cargo"; return; fi
      warn "cargo install failed."
    fi
    warn "No pay-respects package for Solaris and no rust toolchain."
    warn "Install rust then re-run:  pkg install developer/rust/cargo developer/rust/rustc && ./install.sh --pay-respects"
    return
  fi

  info "Installing pay-respects..."

  # 1) distro package (Fedora COPR / future apt) -- quiet miss, keep going
  case "$PKG" in
    dnf) if sudo dnf install -y pay-respects 2>/dev/null; then ok "installed via dnf"; return; fi ;;
    apt) if sudo apt-get install -y pay-respects 2>/dev/null; then ok "installed via apt"; return; fi ;;
  esac

  # 2) cargo, if the box already has a rust toolchain
  if command -v cargo &>/dev/null; then
    info "rust toolchain detected -- installing via cargo..."
    if _cargo_payrespects; then ok "pay-respects installed via cargo"; return; fi
    warn "cargo install failed -- falling back to prebuilt binary"
  fi

  # 3) upstream prebuilt-binary installer (x86_64 / aarch64 Linux)
  info "Installing prebuilt binary via upstream install script..."
  curl -fsSL https://raw.githubusercontent.com/iffse/pay-respects/main/install.sh | sh \
    && ok "pay-respects installed (prebuilt binary)" \
    || die "pay-respects install failed."
}

# ============================================================
# MODULE: ssh
# ============================================================
install_ssh() {
  info "Deploying sshd hardening config..."
  SSHD_D="/etc/ssh/sshd_config.d"

  if [ "$DISTRO_FAMILY" = "freebsd" ]; then
    # Base sshd_config ships WITHOUT an Include directive -- add one at the top.
    # OpenSSH is first-match-wins, so a top-of-file Include lets the drop-in
    # override base defaults. Requires FreeBSD 13.0+ (OpenSSH >= 8.0).
    $SUDO mkdir -p "$SSHD_D"
    if ! grep -q '^Include[[:space:]]*/etc/ssh/sshd_config.d/' /etc/ssh/sshd_config; then
      backup="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
      $SUDO cp /etc/ssh/sshd_config "$backup"
      warn "Backed up sshd_config -> $backup"
      tmp=$(mktemp)
      printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n' | cat - /etc/ssh/sshd_config > "$tmp"
      $SUDO cp "$tmp" /etc/ssh/sshd_config
      $SUDO chmod 644 /etc/ssh/sshd_config
      rm -f "$tmp"
      warn "Prepended Include directive to /etc/ssh/sshd_config"
    fi
    $SUDO cp "$SCRIPT_DIR/ssh/sshd_hardening.conf" "$SSHD_D/99-hardening.conf"
    $SUDO chmod 600 "$SSHD_D/99-hardening.conf"
    ok "Deployed -> $SSHD_D/99-hardening.conf"
    $SUDO sshd -t && $SUDO service sshd restart \
      && ok "sshd hardened and restarted" \
      || die "sshd config validation failed! Fix before restarting."
    return
  fi

  if [ "$DISTRO_FAMILY" = "solaris" ]; then
    # sshd binary isn't on $PATH by default; sshd is SMF-managed, not systemd.
    SSHD_BIN="/usr/lib/ssh/sshd"
    $SUDO mkdir -p "$SSHD_D"
    # Native Solaris /usr/bin/grep has no [[:space:]] (pre-XPG4 BRE) -- use `.` instead
    if ! grep -q '^Include.*sshd_config\.d' /etc/ssh/sshd_config; then
      backup="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
      $SUDO cp /etc/ssh/sshd_config "$backup"
      warn "Backed up sshd_config -> $backup"
      tmp=$(mktemp)
      printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n' | cat - /etc/ssh/sshd_config > "$tmp"
      $SUDO cp "$tmp" /etc/ssh/sshd_config
      $SUDO chmod 644 /etc/ssh/sshd_config
      rm -f "$tmp"
      warn "Prepended Include directive to /etc/ssh/sshd_config"
    fi
    $SUDO cp "$SCRIPT_DIR/ssh/sshd_hardening.conf" "$SSHD_D/99-hardening.conf"
    $SUDO chmod 600 "$SSHD_D/99-hardening.conf"
    ok "Deployed -> $SSHD_D/99-hardening.conf"
    $SUDO "$SSHD_BIN" -t \
      && $SUDO svcadm restart svc:/network/ssh:default \
      && ok "sshd hardened and restarted (SMF)" \
      || die "sshd config validation failed! Fix before restarting."
    return
  fi

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

  if [ "$DISTRO_FAMILY" = "freebsd" ]; then
    # sudo is a package on FreeBSD; config lives under /usr/local/etc
    command -v sudo &>/dev/null || pkg_install sudo
    TARGET="/usr/local/etc/sudoers.d/10-wheel-hardening"
    $SUDO mkdir -p /usr/local/etc/sudoers.d
    $SUDO cp "$SCRIPT_DIR/sudo/10-wheel-hardening" "$TARGET"
    $SUDO chmod 440 "$TARGET"
    if ! $SUDO grep -Eq '^[@#]includedir[[:space:]]+/usr/local/etc/sudoers.d' /usr/local/etc/sudoers; then
      warn "sudoers has no includedir -- add manually: @includedir /usr/local/etc/sudoers.d"
    fi
    [ -f /usr/local/etc/sudoers.d/90-cloud-init-users ] \
      && $SUDO rm /usr/local/etc/sudoers.d/90-cloud-init-users \
      && warn "Removed /usr/local/etc/sudoers.d/90-cloud-init-users (cloud-init NOPASSWD)"
    $SUDO visudo -cf "$TARGET" \
      && ok "sudoers drop-in deployed: $TARGET" \
      || die "sudoers syntax error! Check $TARGET"
    return
  fi

  if [ "$DISTRO_FAMILY" = "solaris" ]; then
    command -v sudo &>/dev/null || pkg_install sudo
    TARGET="/etc/sudoers.d/10-wheel-hardening"
    $SUDO mkdir -p /etc/sudoers.d
    $SUDO cp "$SCRIPT_DIR/sudo/10-wheel-hardening" "$TARGET"
    $SUDO chmod 440 "$TARGET"
    # Native Solaris /usr/bin/grep has neither -E nor [[:space:]] -- use `.` instead
    if ! $SUDO grep -q '^[@#]includedir.*sudoers\.d' /etc/sudoers; then
      warn "sudoers has no includedir -- add manually: @includedir /etc/sudoers.d"
    fi
    warn "Solaris has no 'wheel' group by default -- create it and add users manually"
    $SUDO visudo -cf "$TARGET" \
      && ok "sudoers drop-in deployed: $TARGET" \
      || die "sudoers syntax error! Check $TARGET"
    return
  fi

  TARGET="/etc/sudoers.d/10-wheel-hardening"
  sudo cp "$SCRIPT_DIR/sudo/10-wheel-hardening" "$TARGET"
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
  --pay-respects  pay-respects (Rust thefuck replacement); alias: --thefuck
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
    "payrespects:pay-respects   -> Rust thefuck replacement (press f)" \
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
    --pay-respects|--payrespects) install_payrespects ;;
    --thefuck) warn "--thefuck is deprecated -> installing pay-respects instead"; install_payrespects ;;
    --ssh)     install_ssh ;;
    --sudo)    install_sudo ;;
    --help|-h) usage; exit 0 ;;
    *) warn "Unknown: $arg"; usage; exit 1 ;;
  esac
done

[ "$DO_ALL" -eq 1 ] && install_motd && install_zsh && install_payrespects && install_ssh && install_sudo

echo -e "\nDone.\n"
