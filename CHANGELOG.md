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

## [1.0.1] - 2026-04-19

### Fixed
- Debian/Ubuntu MOTD: enforce `UsePAM yes` (broken by passwordless SSH guides)
- Debian/Ubuntu MOTD: rewrite `pam.d/sshd` motd lines to correct two-line sequence
- `ssh/sshd_hardening.conf`: explicit `UsePAM yes` to prevent regression

## [1.1.0] - 2026-07-30

### Changed
- **Replaced `thefuck` with [pay-respects](https://github.com/iffse/pay-respects)** —
  `thefuck` is abandoned upstream and hard-fails on Python 3.12+ (distutils removed
  per PEP 632, no fallback). pay-respects is a Rust rewrite: single static binary,
  sub-millisecond suggestions, zero Python runtime. New flag `--pay-respects`.
- Install strategy: distro package → `cargo` (if a rust toolchain exists) →
  upstream prebuilt-binary installer. Drops the `pipx` + `python3.11` fallback chain.
- `zsh/zshrc`: thefuck hook swapped for pay-respects (`f` / `^f` → `fuck`), with a
  commented-out `request-ai` block for routing the AI fallback at a local Ollama
  endpoint (OpenAI-compatible `/v1/chat/completions`), plus `_PR_AI_DISABLE` note.
- Renamed `sudo/10-marek-hardening` → `sudo/10-wheel-hardening` (matches the
  deployed target filename; drop-in was already `%wheel`-scoped).

### Added
- `--thefuck` retained as a **deprecated alias** for `--pay-respects` (prints a
  warning) so existing one-liners / automation keep working.

### Fixed
- README structure block: `motd-preview.svg` → `motd-preview.png` (actual asset).