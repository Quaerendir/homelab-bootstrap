# Changelog

## [Unreleased]

### Added
- **Solaris 11.4 support** across all modules:
  - Package manager: IPS `pkg` detected via `uname -s = SunOS` (`PKG="ips"`, distinct
    from FreeBSD's `pkg` name/syntax), with a common-name -> FMRI map
    (`bash`, `zsh`, `git`, `curl`, `sudo`) in `pkg_install()`; exit code 4
    ("no changes were made") treated as success, not failure.
  - `--motd`: new `motd/motd-solaris.sh` (kstat-based CPU/memory/ZFS ARC/uptime,
    no `/proc`, no `free`), hooked into `/etc/profile` and `/etc/zprofile`,
    truncates `/etc/motd` since sshd's `PrintMotd` reads it directly.
  - `--ssh`: prepends `Include /etc/ssh/sshd_config.d/*.conf` if missing (backs up
    first), validates with the full `/usr/lib/ssh/sshd` path (not on `$PATH` by
    default), restarts via `svcadm restart svc:/network/ssh:default` (SMF, not
    systemd/service).
  - `--sudo`: deploys `/etc/sudoers.d/10-wheel-hardening`, warns if `/etc/sudoers`
    has no `includedir` and if the `wheel` group doesn't exist (not present by
    default on Solaris).
  - `--zsh`: sets the login shell via `usermod -s` instead of `chsh` (Solaris has
    no `chsh(1)`).
  - `--pay-respects`: no IPS package and no prebuilt Solaris/illumos binary
    upstream -- cargo-only install path, same as the FreeBSD fallback.
  - All 4 modules verified live over SSH against a real Solaris 11.4 box
    (`pkg`, `kstat`, `df`, `route`, `ifconfig`, `sshd`, `svcadm`, `usermod`
    output all confirmed directly), each run twice to confirm idempotency.
  - README: documented a client-side SSH gotcha found during that testing --
    Solaris 11.4 x86 only ships a handful of locales (no `pl_PL`/`en_GB`, and
    no installable package for the missing ones), so a client that forwards
    `LANG`/`LC_*` (common OpenSSH default) triggers a perl locale warning from
    `kstat` and other perl-based tools on every login. A `SendEnv -LANG -LC_*`
    override doesn't fix it (SendEnv accumulates across config files instead
    of first-match-wins); `SetEnv LANG=... LC_ADDRESS=... ...` pinned to an
    installed locale does.

### Fixed
- Solaris `pay-respects` fallback hint referenced a nonexistent `developer/rust`
  FMRI -- corrected to `developer/rust/cargo` + `developer/rust/rustc` (Rust is
  split into separate compiler/toolchain packages on Solaris's IPS).
- Solaris `--motd` hook was never idempotent: native `/usr/bin/grep` has no
  `-F` (and `/usr/bin/fgrep` has no `-q`), so `grep -qF` always errored and the
  hook block got re-appended to `/etc/profile` on every run. Switched to plain
  `grep -q` (the search string has no regex metacharacters that matter here).
- Solaris `--ssh`'s `Include` check and `--sudo`'s `includedir` check used
  `[[:space:]]` (and `-E` for the latter) -- unsupported by native Solaris
  grep, a pre-XPG4 SVR4 grep. Both always reported "not found", causing a
  duplicate `Include` line to be prepended on every `--ssh` run. Replaced with
  a plain BRE using `.` in place of the character class.
- `pkg_install()`'s Solaris/`ips` branch computed `rc=$?` right after
  `! $SUDO pkg install ...`, which captures the *negated* status from `!`
  (always 0 inside that branch), not pkg's real exit code -- so a successful
  "already installed" run was misreported as "pkg install failed (exit 0)".
  Fixed with the `cmd || rc=$?` idiom, which preserves both the real exit
  code and `set -e`'s exemption for non-final members of an `||` list.

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