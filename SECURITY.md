# Security Policy

## What this repo does to your system

- **SSH hardening**: disables root login and password auth — make sure your SSH key is in `authorized_keys` BEFORE running `--ssh`
- **sudo hardening**: removes NOPASSWD — you will need a password for sudo after `--sudo`
- **MOTD**: read-only, just displays info
- **zsh**: installs packages and modifies `~/.zshrc` (backs up the original)

## Reporting issues

Open a GitHub issue. For sensitive security findings, email directly.

## Before running on production

1. Review all files in this repo — they're short, read them
2. Run `--ssh` only after confirming your public key is in `~/.ssh/authorized_keys`
3. Test in a VM first
