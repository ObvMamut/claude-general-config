#!/bin/sh
# SessionStart hook: inject a compact snapshot of the repo into context.
#
# Budget: under ~200ms and ~20 lines. Silent outside a git repo.
# Always exits 0.

set -u

input=$(cat 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$cwd" ] || cwd=$PWD
[ -d "$cwd" ] || exit 0

# Opportunistic cleanup of stale per-session edit markers (older than a day).
mark_dir="${TMPDIR:-/tmp}/claude-session-edits"
[ -d "$mark_dir" ] && find "$mark_dir" -type f -mtime +1 -delete 2>/dev/null

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(timeout 1s git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null) \
    || branch=$(timeout 1s git -C "$cwd" rev-parse --short HEAD 2>/dev/null) \
    || branch="(detached)"

status=$(timeout 1s git -C "$cwd" --no-optional-locks status --porcelain=v1 2>/dev/null) || status=""
if [ -n "$status" ]; then
    modified=$(printf '%s\n' "$status" | grep -cv '^??' 2>/dev/null || true)
    untracked=$(printf '%s\n' "$status" | grep -c  '^??' 2>/dev/null || true)
else
    modified=0
    untracked=0
fi

printf '## Repo snapshot\n\n'
printf -- '- Branch: %s (%s modified, %s untracked)\n' "$branch" "${modified:-0}" "${untracked:-0}"

recent=$(timeout 1s git -C "$cwd" --no-optional-locks log --oneline -3 --no-decorate 2>/dev/null) || recent=""
if [ -n "$recent" ]; then
    printf -- '- Recent commits:\n'
    printf '%s\n' "$recent" | sed 's/^/    /'
fi

if [ "${modified:-0}" -gt 0 ] 2>/dev/null; then
    printf -- '- Uncommitted (tracked):\n'
    printf '%s\n' "$status" | grep -v '^??' 2>/dev/null | head -8 | sed 's/^/    /'
fi

for todo in TODO.md TODO.txt; do
    if [ -f "$cwd/$todo" ]; then
        printf -- '- %s exists (%s lines)\n' "$todo" "$(wc -l < "$cwd/$todo" 2>/dev/null || echo '?')"
        break
    fi
done

exit 0
