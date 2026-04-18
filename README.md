# homelab-bootstrap

Modular setup script for RHEL / Fedora / Debian-based servers.

## Quick start

```bash
git clone <your-private-repo-url> homelab-bootstrap
cd homelab-bootstrap
chmod +x install.sh
./install.sh
```

No arguments = interactive menu. Pick modules per host.

## Modules

| Flag | What it does |
|------|-------------|
| `--motd` | Dynamic MOTD -> `/etc/profile.d/motd.sh`, silences RH Insights |
| `--zsh` | zsh + Oh My Zsh + plugins + `.zshrc` |
| `--thefuck` | thefuck via pipx (Python 3.11 to avoid distutils issue) |
| `--ssh` | sshd hardening drop-in, validates + restarts sshd |
| `--sudo` | sudoers drop-in, removes cloud-init NOPASSWD |
| `--all` | All modules in sequence |

## Examples

```bash
./install.sh                  # interactive menu
./install.sh --all            # everything
./install.sh --zsh --motd     # new VM, just comfort
./install.sh --ssh --sudo     # production hardening only
```

## Structure

```
homelab-bootstrap/
├── install.sh
├── README.md
├── .gitignore
├── motd/
│   └── motd.sh
├── zsh/
│   └── zshrc
├── ssh/
│   └── sshd_hardening.conf
└── sudo/
    └── 10-marek-hardening
```

## Notes

- `.zshrc` is backed up before overwriting
- `--ssh` runs `sshd -t` before restart -- safe
- `--sudo` runs `visudo -cf` before deployment -- safe
- Idempotent: skips already-installed components
- Tested on RHEL 9/10, Fedora, Debian/Ubuntu
