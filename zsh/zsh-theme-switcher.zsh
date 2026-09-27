# Interactive oh-my-zsh theme switcher via fzf.
# Usage:
#   theme            interactive picker (fzf) with live source preview
#   theme list       print the curated theme names
#   theme <name>     set directly, no picker (e.g. theme robbyrussell)

_theme_zshrc="${ZDOTDIR:-$HOME}/.zshrc"

_theme_curated=(
  quickterm
  xiong-chiamiov-plus
  robbyrussell
  agnoster
  avit
  bira
  af-magic
  refined
  sorin
  gnzh
  linuxonly
  clean-term
  zsh2000
  "quantum/quantum"
)

_theme_file_for() {
  local name="$1" f
  f="$ZSH/custom/themes/${name}.zsh-theme"
  [[ -f "$f" ]] && { print -r -- "$f"; return 0 }
  f="$ZSH/themes/${name}.zsh-theme"
  [[ -f "$f" ]] && { print -r -- "$f"; return 0 }
  return 1
}

theme() {
  local sel f

  case "$1" in
    list)
      printf '%s\n' "${_theme_curated[@]}"
      return 0
      ;;
    "")
      local -a entries
      local name
      for name in "${_theme_curated[@]}"; do
        f="$(_theme_file_for "$name")" || continue
        entries+=("${name}"$'\t'"${f}")
      done
      sel=$(printf '%s\n' "${entries[@]}" \
        | fzf --prompt='theme> ' --delimiter='\t' --with-nth=1 \
              --preview='cat {2}' --preview-window=right:60%:wrap \
        | cut -f1)
      [[ -z "$sel" ]] && return 0
      ;;
    *)
      sel="$1"
      ;;
  esac

  if ! _theme_file_for "$sel" >/dev/null; then
    echo "theme: unknown theme '$sel' (try: theme list)" >&2
    return 1
  fi

  sed -i -E "s|^ZSH_THEME=.*|ZSH_THEME=\"${sel}\"|" "$_theme_zshrc"
  echo "Theme set to '$sel'. Reloading zsh..."
  exec zsh
}
