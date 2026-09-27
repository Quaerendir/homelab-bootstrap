# quickterm.zsh-theme
# oh-my-zsh port of the oh-my-posh "quick-term" theme (quick-term.omp.json):
# ╭─[os] user  path  git-status
# ╰─ $                              exec-time  HH:MM:SS  (right side)

zmodload zsh/datetime 2>/dev/null
setopt prompt_subst

typeset -g QT_SEP='\ue0b0'   # powerline separator (points right)
typeset -g QT_SEP_L='\ue0b1' # thin separator (path components)

# --- colors, lifted straight from quick-term.omp.json ---
typeset -g QT_OS_BG='#d75f00'   QT_OS_FG='#f2f3f8'
typeset -g QT_USER_BG='#e4e4e4' QT_USER_FG='#4e4e4e'
typeset -g QT_PATH_BG='#0087af' QT_PATH_FG='#f2f3f8'
typeset -g QT_GIT_BG='#378504'  QT_GIT_FG='#f2f3f8'
typeset -g QT_GIT_DIRTY_BG='#a97400'
typeset -g QT_GIT_DIVERGED_BG='#54433a'
typeset -g QT_GIT_AHEADBEHIND_BG='#744d89'
typeset -g QT_TIME_BG='#e4e4e4' QT_TIME_FG='#585858'
typeset -g QT_CLOCK_BG='#d75f00' QT_CLOCK_FG='#f2f3f8'

# --- left-side powerline chain (shared background across segments) ---
QT_CURRENT_BG='NONE'

qt_segment() {
  local bg=$1 fg=$2 text=$3
  if [[ $QT_CURRENT_BG != 'NONE' ]]; then
    echo -n "%{%K{$bg}%F{$QT_CURRENT_BG}%}$QT_SEP%{%F{$fg}%}$text"
  else
    echo -n "%{%K{$bg}%F{$fg}%}$text"
  fi
  QT_CURRENT_BG=$bg
}

qt_end() {
  [[ $QT_CURRENT_BG != 'NONE' ]] && echo -n "%{%k%F{$QT_CURRENT_BG}%}$QT_SEP"
  echo -n "%{%f%k%}"
  QT_CURRENT_BG='NONE'
}

# --- floating diamond segment (eases out of/into transparent, e.g. git) ---
qt_diamond() {
  local bg=$1 fg=$2 text=$3
  if [[ $QT_CURRENT_BG != 'NONE' ]]; then
    echo -n "%{%k%F{$QT_CURRENT_BG}%}$QT_SEP"
  fi
  echo -n "%{%K{$bg}%F{$fg}%}$text%{%k%F{$bg}%}$QT_SEP%{%f%}"
  QT_CURRENT_BG='NONE'
}

# --- OS icon ---
qt_os_icon() {
  local id=''
  case "$(uname -s)" in
    Darwin) print -n '\ue711'; return ;;
    FreeBSD) print -n '\uf30c'; return ;;
  esac
  [[ -r /etc/os-release ]] && id=$(source /etc/os-release 2>/dev/null; print -n "$ID")
  case "$id" in
    ubuntu) print -n '\uf31c' ;;
    debian) print -n '\uf306' ;;
    arch) print -n '\uf303' ;;
    fedora) print -n '\uf30a' ;;
    *) print -n '\ue712' ;;
  esac
}

prompt_qt_top() {
  # NOTE: call the qt_* segment functions directly (not via $(...)) --
  # command substitution forks a subshell in zsh, so a QT_CURRENT_BG
  # write inside one would never be visible to the next segment call.
  QT_CURRENT_BG='NONE'
  print -n "%{%F{$QT_OS_BG}%}\u256d\u2500\ue0b2%{%f%}"
  qt_segment "$QT_OS_BG" "$QT_OS_FG" " $(qt_os_icon) "
  qt_segment "$QT_USER_BG" "$QT_USER_FG" " %n "
  qt_segment "$QT_PATH_BG" "$QT_PATH_FG" " $(qt_path) "
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    qt_git
  else
    qt_end
  fi
  qt_right_overlay
}

qt_path() {
  local dir="${PWD/#$HOME/~}"
  local -a parts
  parts=("${(s:/:)dir}")
  local n=${#parts}
  if (( n > 3 )); then
    parts=('…' "${parts[-3]}" "${parts[-2]}" "${parts[-1]}")
  fi
  local sep=$' \ue0b1 '
  print -n "${(pj.$sep.)parts}"
}

qt_git() {
  git rev-parse --is-inside-work-tree &>/dev/null || return
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || branch=$(git rev-parse --short HEAD 2>/dev/null)
  [[ -z $branch ]] && return

  local working_dirty='' staged_dirty=''
  [[ -n "$(git diff --name-only 2>/dev/null)" ]] && working_dirty=1
  [[ -n "$(git diff --name-only --cached 2>/dev/null)" ]] && staged_dirty=1

  local ahead=0 behind=0
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null; then
    ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null)
    behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null)
  fi

  local bg=$QT_GIT_BG
  if (( ahead > 0 && behind > 0 )); then
    bg=$QT_GIT_DIVERGED_BG
  elif (( ahead > 0 || behind > 0 )); then
    bg=$QT_GIT_AHEADBEHIND_BG
  elif [[ -n $working_dirty || -n $staged_dirty ]]; then
    bg=$QT_GIT_DIRTY_BG
  fi

  local gs=''
  (( ahead > 0 )) && gs+=" \u2b06$ahead"
  (( behind > 0 )) && gs+=" \u2b07$behind"
  [[ -n $working_dirty ]] && gs+=" \uf044 $(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')"
  [[ -n $staged_dirty ]] && gs+=" \uf046 $(git diff --name-only --cached 2>/dev/null | wc -l | tr -d ' ')"

  qt_diamond "$bg" "$QT_GIT_FG" " \uf418 ${branch}${gs} "
}

prompt_qt_bottom() {
  print -nP "%{%F{$QT_OS_BG}%}\u2570\u2500 %(!.#.\$)%{%f%} "
}

# --- execution time + clock (right side of the top line) ---
typeset -g QT_CMD_START=0
typeset -g QT_ELAPSED=''

qt_preexec() { QT_CMD_START=$EPOCHREALTIME }
qt_precmd() {
  if (( QT_CMD_START > 0 )); then
    local d=$(( EPOCHREALTIME - QT_CMD_START ))
    QT_CMD_START=0
    if (( d < 1 )); then
      QT_ELAPSED="$(printf '%.0f' $(( d * 1000 )) )ms"
    elif (( d < 60 )); then
      QT_ELAPSED="$(printf '%.1f' $d)s"
    else
      local mins=$(printf '%d' $(( d / 60 )) )
      local secs=$(printf '%d' $(( d - mins * 60 )) )
      QT_ELAPSED="${mins}m${secs}s"
    fi
  else
    QT_ELAPSED='0ms'
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec qt_preexec
add-zsh-hook precmd qt_precmd

# Right-aligned exec-time + clock, drawn on the TOP line via cursor
# save/move/restore (RPROMPT would instead align to the prompt's *last*
# physical line, which is the "\u2570\u2500 $" line -- not what quick-term does).
qt_rgb() {
  local hex=${1#\#}
  print -n "$(( 16#${hex[1,2]} ));$(( 16#${hex[3,4]} ));$(( 16#${hex[5,6]} ))"
}

qt_right_overlay() {
  local time_txt=$' \uebA2 '"${QT_ELAPSED}"$' '
  local clock_txt=$' \uf073 '"$(date +%H:%M:%S)"$' '
  local sep=$'\ue0b2'
  local trail=$'\ue0b0'

  local plain="${sep}${time_txt}${sep}${clock_txt}${trail}"
  local width=${#plain}
  local cols=${COLUMNS:-80}
  local col=$(( cols - width + 1 ))
  (( col < 1 )) && col=1

  local time_bg=$(qt_rgb "$QT_TIME_BG") time_fg=$(qt_rgb "$QT_TIME_FG")
  local clock_bg=$(qt_rgb "$QT_CLOCK_BG") clock_fg=$(qt_rgb "$QT_CLOCK_FG")

  local raw=""
  raw+=$'\e[38;2;'"${time_bg}"$'m'"${sep}"
  raw+=$'\e[48;2;'"${time_bg}"$'m'$'\e[38;2;'"${time_fg}"$'m'"${time_txt}"
  raw+=$'\e[48;2;'"${time_bg}"$'m'$'\e[38;2;'"${clock_bg}"$'m'"${sep}"
  raw+=$'\e[48;2;'"${clock_bg}"$'m'$'\e[38;2;'"${clock_fg}"$'m'"${clock_txt}"
  raw+=$'\e[0m'$'\e[38;2;'"${clock_bg}"$'m'"${trail}"
  raw+=$'\e[0m'

  local save=$'\e[s' restore=$'\e[u'
  local moveto=$'\e['"${col}"$'G'

  print -n "%{${save}${moveto}${raw}${restore}%}"
}

PROMPT='$(prompt_qt_top)
$(prompt_qt_bottom)'
