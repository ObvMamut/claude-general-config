#!/bin/sh
# Stop hook: one advisory line about work left uncommitted.
#
# ADVISORY ONLY. Always exits 0 and never emits a blocking decision, so it can
# never trap a session in a loop.
#
# Stays quiet unless this session actually edited a file (format-edited.sh drops
# a per-session marker). A read-only or conversational session says nothing.

set -u

input=$(cat 2>/dev/null) || exit 0

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$sid" ] || exit 0

mark="${TMPDIR:-/tmp}/claude-session-edits/$sid"
[ -f "$mark" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$cwd" ] || cwd=$PWD
[ -d "$cwd" ] || exit 0

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

status=$(timeout 1s git -C "$cwd" --no-optional-locks status --porcelain=v1 -uno 2>/dev/null) || exit 0
[ -n "$status" ] || exit 0

# -uno already excludes untracked, so every remaining line is a change
n=$(printf '%s\n' "$status" | grep -c . 2>/dev/null || true)
[ "${n:-0}" -gt 0 ] 2>/dev/null || exit 0

files=$(printf '%s\n' "$status" | awk '{print $NF}' | head -3 | tr '\n' ' ')
printf 'Uncommitted: %s file(s) — %s\n' "$n" "${files% }"

exit 0
