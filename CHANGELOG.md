# Changelog

## [Unreleased]

### Added
- **NetBSD 10.1 support** across all modules:
  - Package manager: pkgsrc via `pkgin` detected via `uname -s = NetBSD`
    (`PKG="pkgin"`); bootstraps `pkgin` itself via `pkg_add` + `PKG_PATH` against
    the official binary package CDN if missing (a fresh NetBSD install has
    neither `pkgin` nor any package manager configured out of the box).
  - `--motd`: new `motd/motd-netbsd.sh` (`sysctl`/`vmstat -s` based CPU/memory/
    uptime, no `/proc`, no `free`, no ZFS), hooked into `/etc/profile` and
    `/usr/pkg/etc/zprofile` (pkgsrc zsh's compiled-in global zprofile path,
    confirmed via `strings` against the actual binary), truncates `/etc/motd`
    since sshd's `PrintMotd` reads it directly. Explicitly prepends
    `/sbin:/usr/sbin` to `$PATH` inside the script itself -- unlike FreeBSD,
    NetBSD's compiled-in default `$PATH` (used before `~/.profile` extends it)
    excludes both, so every command silently failed without this.
  - `--ssh`: prepends `Include /etc/ssh/sshd_config.d/*.conf` if missing (backs
    up first, same as FreeBSD), restarts via `/etc/rc.d/sshd restart` (rc.d, not
    systemd/SMF/`service` -- NetBSD has no `service` command at all).
  - `--sudo`: deploys `/usr/pkg/etc/sudoers.d/10-wheel-hardening` -- sudo is a
    pkgsrc package (config lives under the `/usr/pkg` prefix, not `/etc`), and
    pkgsrc's `sudoers` already ships with `@includedir` wired in, so (unlike
    FreeBSD/Solaris) there's nothing to check or warn about there. `wheel`
    group already exists by default (root is a member out of the box).
  - `--zsh`: needs no special case -- NetBSD ships `chsh(1)` in base, so the
    generic (RHEL/Debian) code path just works.
  - `--pay-respects`: no pkgsrc package and no prebuilt NetBSD binary upstream
    -- cargo-only install path, same as the FreeBSD/Solaris fallback.
  - All modules verified live over SSH against a real NetBSD 10.1/amd64 VM
    (`pkgin`, `sysctl`, `vmstat`, `route`, `ifconfig`, `sshd`, `rc.d`, `chsh`
    output all confirmed directly), `--motd`/`--sudo` re-run to confirm
    idempotency.

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
- NetBSD `--motd`: `vmstat -s | awk '/pages free/{print $1}'` matched *two*
  lines ("pages free" and the later "pages freed by daemon" -- "free" is a
  substring of "freed") and returned both numbers, breaking the `$(( ))`
  memory calculation with "variable contains non-numeric value". Anchored the
  pattern on `$` (`/pages free$/`) to match only the exact line.
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
- `motd.sh` and `motd-debian.sh` showed a blank CPU model on ARM boards
  (Raspberry Pi and most SBCs) -- `/proc/cpuinfo` has no `model name` line on
  ARM, only per-core implementer/part/revision fields, so `CPU_CORES` still
  worked but `CPU_MODEL` came back empty. Added a fallback chain:
  `/proc/device-tree/model` (works across most ARM SBCs, Pi included) first,
  then `/proc/cpuinfo`'s trailing `Model` line (Raspberry Pi's own field) if
  that file isn't present. Verified live on both a Raspberry Pi 4 (AlmaLinux
  8.10 aarch64, `motd.sh`) and a Raspberry Pi 5 (Debian 13 trixie,
  `motd-debian.sh`) -- both went from a blank CPU field to the correct
  "Raspberry Pi N Model B Rev X.Y" string, deployed live on both boxes.

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