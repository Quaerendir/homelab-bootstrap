# Changelog

## [1.0.0] - 2026-04-18

### Added
- `install.sh` — modular installer with interactive menu and CLI flags
- `--motd` — dynamic MOTD with hostname box, system stats, color-coded RAM/disk
- `--zsh` — zsh + Oh My Zsh + autosuggestions, syntax-highlighting, history-substring-search
- `--thefuck` — pipx install with Python 3.11 fallback (avoids distutils issue on 3.12+)
- `--ssh` — sshd hardening drop-in (no root login, no passwords, keepalive)
- `--sudo` — sudoers drop-in, removes cloud-init NOPASSWD grant
- Auto-detect dnf vs apt
- `.zshrc` backup before overwrite
- `sshd -t` validation before restart
- `visudo -cf` validation before sudoers deployment
