# homelab-bootstrap

Modular, idempotent setup script for RHEL / Fedora / Debian-based servers.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Quaerendir/homelab-bootstrap/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/Quaerendir/homelab-bootstrap.git
cd homelab-bootstrap
./install.sh
```

No arguments = interactive menu. Pick modules per host.

---

## Modules

| Flag | What it does |
|------|-------------|
| `--motd` | Dynamic MOTD -> `/etc/profile.d/motd.sh`, silences RH Insights prompt |
| `--zsh` | zsh + Oh My Zsh + plugins (autosuggestions, syntax-highlighting, history-substring-search) + `.zshrc` |
| `--thefuck` | thefuck via pipx using Python 3.11 (avoids distutils issue on 3.12+) |
| `--ssh` | sshd hardening drop-in — no root, no passwords, keepalive. Validates before restart. |
| `--sudo` | sudoers drop-in — wheel with password. Removes cloud-init NOPASSWD. Validates before deploy. |
| `--all` | All modules in sequence |

## Examples

```bash
./install.sh                  # interactive menu
./install.sh --all            # everything
./install.sh --zsh --motd     # new VM, comfort only
./install.sh --ssh --sudo     # production hardening only
```

## One-liner per module

```bash
# Just MOTD
bash <(curl -fsSL https://raw.githubusercontent.com/Quaerendir/homelab-bootstrap/main/install.sh) --motd

# Just zsh
bash <(curl -fsSL https://raw.githubusercontent.com/Quaerendir/homelab-bootstrap/main/install.sh) --zsh
```

## Structure

```
homelab-bootstrap/
├── install.sh                      # Main installer
├── README.md
├── LICENSE                         # MIT
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── .gitignore
├── motd/
│   └── motd.sh                     # Dynamic MOTD script
├── zsh/
│   └── zshrc                       # .zshrc (OMZ + plugins + history + aliases)
├── ssh/
│   └── sshd_hardening.conf         # sshd drop-in
└── sudo/
    └── 10-marek-hardening          # sudoers drop-in
```

## Compatibility

| Distro | Tested |
|--------|--------|
| RHEL 9 / 10 | yes |
| Fedora 39+ | yes |
| Debian 12 | yes |
| Ubuntu 22.04 / 24.04 | yes |

## Safety

- `.zshrc` backed up before overwriting
- `--ssh` runs `sshd -t` validation before restart
- `--sudo` runs `visudo -cf` before deployment
- All modules are idempotent — safe to re-run
- **Read [SECURITY.md](SECURITY.md) before running `--ssh` or `--sudo` on production**

## License

MIT — see [LICENSE](LICENSE)
