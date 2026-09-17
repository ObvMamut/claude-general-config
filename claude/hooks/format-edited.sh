#!/bin/sh
# PostToolUse hook: format a file Claude just edited.
#
# Only runs a formatter when BOTH are true:
#   * the formatter is installed
#   * the project already uses it (a config/manifest is present)
# Never installs anything, never reformats files the project does not manage.
# Always exits 0: a formatter problem must never interrupt a session.

set -u

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$file" ] && [ -f "$file" ] || exit 0

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || sid=""

# Record that this session edited something, so the Stop hook can stay quiet
# in sessions that only read.
if [ -n "$sid" ]; then
    mark_dir="${TMPDIR:-/tmp}/claude-session-edits"
    mkdir -p "$mark_dir" 2>/dev/null && : > "$mark_dir/$sid" 2>/dev/null
fi

dir=$(dirname "$file")

# Walk up from the file looking for a marker, stopping at $HOME or /.
find_up() {
    d=$dir
    while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
        for marker in "$@"; do
            if [ -e "$d/$marker" ]; then
                printf '%s' "$d"
                return 0
            fi
        done
        d=$(dirname "$d")
    done
    return 1
}

case "$file" in
    *.py)
        command -v ruff >/dev/null 2>&1 || exit 0
        root=$(find_up pyproject.toml ruff.toml .ruff.toml) || exit 0
        grep -q 'ruff' "$root/pyproject.toml" 2>/dev/null \
            || [ -e "$root/ruff.toml" ] || [ -e "$root/.ruff.toml" ] || exit 0
        ruff format -q "$file" >/dev/null 2>&1
        ;;
    *.rs)
        command -v rustfmt >/dev/null 2>&1 || exit 0
        find_up Cargo.toml >/dev/null || exit 0
        rustfmt --quiet "$file" >/dev/null 2>&1
        ;;
    *.go)
        command -v gofmt >/dev/null 2>&1 || exit 0
        find_up go.mod >/dev/null || exit 0
        gofmt -w "$file" >/dev/null 2>&1
        ;;
    *.ts|*.tsx|*.js|*.jsx|*.css|*.json|*.md)
        root=$(find_up .prettierrc .prettierrc.json .prettierrc.js prettier.config.js) || exit 0
        # Only a project-local prettier; never npx, which would hit the network.
        [ -x "$root/node_modules/.bin/prettier" ] || exit 0
        "$root/node_modules/.bin/prettier" --write --log-level silent "$file" >/dev/null 2>&1
        ;;
esac

exit 0
