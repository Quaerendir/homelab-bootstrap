# Contributing

This is a personal homelab bootstrap repo — contributions welcome if they keep the spirit:
- Modular, opt-in installs
- Idempotent (safe to run multiple times)
- Works on RHEL/Fedora and Debian/Ubuntu
- No bloat, no magic

## Adding a module

1. Create a directory: `modules/<name>/`
2. Add your config files there
3. Add an `install_<name>()` function in `install.sh`
4. Add the flag to `usage()` and `interactive_menu()`
5. Document in `README.md`

## Pull requests

Keep PRs focused and small. Test on at least one RHEL-based and one Debian-based system.
