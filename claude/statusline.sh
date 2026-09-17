#!/usr/bin/env bash
# Claude Code statusline.
#
# Design rules (see PLAN.md, section A2):
#   * colours are ANSI palette indices 0-15 only, never hex, so the line follows
#     whatever palette chroma has generated for Alacritty
#   * exactly one jq process per render
#   * every numeric comparison is integer-guarded
#   * the git call is hard-timeouted; a slow repo can never stall the UI
#   * fail-open: on any error print a minimal line rather than nothing
#
# Fields are joined with US (0x1f), not tab: tab is an IFS-whitespace character
# in bash, so `read` would collapse runs of them and swallow empty fields.

input=$(cat)
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

data=$(
  printf '%s' "$input" | jq -r --slurpfile s "$settings" '
    def s0: ($s[0] // {});
    [ (.workspace.current_dir // .cwd // ""),
      (.model.display_name // "Claude"),
      (.context_window.used_percentage // "" | tostring),
      (.context_window.exceeds_200k_tokens // false | tostring),
      ((.output_style // "") | if type == "object" then (.name // "") else tostring end),
      (.cost.total_cost_usd // 0 | tostring),
      (.cost.total_duration_ms // 0 | tostring),
      (.cost.total_lines_added // 0 | tostring),
      (.cost.total_lines_removed // 0 | tostring),
      ((s0.effortLevel // "") | tostring)
    ] | join("")' 2>/dev/null
) || data=""

if [ -z "$data" ]; then
  printf '\033[38;5;8mclaude\033[0m'
  exit 0
fi

IFS=$'\037' read -r dir model ctx exceeds ostyle cost dur added removed effort <<<"$data"

# --- helpers -----------------------------------------------------------------
ESC=$'\033'
SEP=$''
DIM="${ESC}[38;5;7m"
OUT=""
PREV=""

push() { # bg fg text
  [ -z "${3:-}" ] && return 0
  if [ -n "$PREV" ]; then
    OUT+="${ESC}[38;5;${PREV}m${ESC}[48;5;${1}m${SEP}"
  fi
  OUT+="${ESC}[48;5;${1}m${ESC}[38;5;${2}m ${3} "
  PREV="$1"
}

finish() {
  [ -n "$PREV" ] && OUT+="${ESC}[0m${ESC}[38;5;${PREV}m${SEP}${ESC}[0m"
  printf '%s' "$OUT"
}

# Round a possibly-float, possibly-empty value to an integer. Always succeeds.
as_int() {
  case "${1:-}" in
    ''|null) printf '0' ;;
    *) LC_ALL=C printf '%.0f' "$1" 2>/dev/null || printf '0' ;;
  esac
}

# --- dir: keep at most the last two components -------------------------------
short="${dir/#$HOME/\~}"
if [ -n "$short" ]; then
  base="${short##*/}"
  rest="${short%/*}"
  if [ -n "$rest" ] && [ "$rest" != "$short" ]; then
    parent="${rest##*/}"
    prefix="${rest%/$parent}"
    if [ -z "$parent" ] || [ "$rest" = "$parent" ] || [ -z "$prefix" ]; then
      # two components or fewer: nothing is actually being elided
      short="${rest:-/}/$base"
    else
      short="…/$parent/$base"
    fi
  fi
  push 4 0 "$short"
fi

# --- git ---------------------------------------------------------------------
if [ -n "$dir" ] && [ -d "$dir" ]; then
  gs=$(timeout 0.4s git -C "$dir" --no-optional-locks status --porcelain=v1 -b 2>/dev/null) || gs=""
  if [ -n "$gs" ]; then
    head_line="${gs%%$'\n'*}"
    branch="${head_line#\#\# }"
    ahead=""
    case "$branch" in
      "No commits yet on "*)
        branch="${branch#No commits yet on }"
        ahead=" (new)"
        ;;
      *"["*)
        ahead=" ${branch#*\[}"
        ahead="${ahead%\]}"
        ;;
    esac
    branch="${branch%% *}"
    branch="${branch%%...*}"
    # tracked-but-modified and untracked counted separately, as p10k does
    # porcelain marks an unstaged edit as " M file" (leading space), so match
    # by exclusion rather than by a leading non-space character
    body=$(printf '%s\n' "$gs" | grep -v '^##' 2>/dev/null || true)
    if [ -n "$body" ]; then
      mod_n=$(as_int "$(printf '%s\n' "$body" | grep -cv '^??' 2>/dev/null || true)")
      unt_n=$(as_int "$(printf '%s\n' "$body" | grep -c  '^??' 2>/dev/null || true)")
    else
      mod_n=0; unt_n=0
    fi
    marks=""
    [ "$mod_n" -gt 0 ] && marks+=" *${mod_n}"
    [ "$unt_n" -gt 0 ] && marks+=" ?${unt_n}"
    if [ -n "$marks" ]; then
      push 3 0 "${branch}${ahead}${marks}"
    else
      push 2 0 "${branch}${ahead}"
    fi
  fi
fi

# --- model + effort ----------------------------------------------------------
label="$model"
case "$effort" in
  ''|null|medium) ;;
  xhigh) label+=" ++" ;;
  high)  label+=" +"  ;;
  *)     label+=" $effort" ;;
esac
push 5 0 "$label"

# --- meta zone: output style, context, diff, cost ----------------------------
parts=()

case "$ostyle" in
  ''|null|default) ;;
  *) parts+=("[$ostyle]") ;;
esac

if [ -n "$ctx" ] && [ "$ctx" != "null" ]; then
  ctx_i=$(as_int "$ctx")
  if   [ "$exceeds" = "true" ] || [ "$ctx_i" -ge 80 ]; then c=1
  elif [ "$ctx_i" -ge 50 ]; then c=3
  else c=2
  fi
  warn=""
  [ "$exceeds" = "true" ] && warn="!"
  parts+=("${ESC}[38;5;${c}m${ctx_i}%${warn}${DIM}")
fi

add_i=$(as_int "$added")
rem_i=$(as_int "$removed")
if [ "$add_i" -gt 0 ] || [ "$rem_i" -gt 0 ]; then
  parts+=("${ESC}[38;5;2m+${add_i}${DIM}/${ESC}[38;5;1m-${rem_i}${DIM}")
fi

cost_f=$(LC_ALL=C printf '%.2f' "${cost:-0}" 2>/dev/null || printf '0.00')
mins=$(( $(as_int "${dur:-0}") / 60000 ))
if [ "$cost_f" != "0.00" ] || [ "$mins" -gt 0 ]; then
  money="\$$cost_f"
  [ "$mins" -gt 0 ] && money+=" ${mins}m"
  parts+=("$money")
fi

if [ "${#parts[@]}" -gt 0 ]; then
  meta="${parts[0]}"
  for p in "${parts[@]:1}"; do meta+="  $p"; done
  push 8 7 "$meta"
fi

finish
