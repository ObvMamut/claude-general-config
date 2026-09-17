#!/bin/sh
# Verify that everything install.sh claims is actually true.
# Exits non-zero on the first hard failure; warnings do not fail the run.

set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
claude_dir=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
settings="$claude_dir/settings.json"
fail=0
warn=0

ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
note() { printf '  warn  %s\n' "$*"; warn=$((warn + 1)); }

need() { command -v "$1" >/dev/null 2>&1 || { bad "missing tool: $1"; return 1; }; }

echo "Checking $claude_dir"

need jq || exit 1
need git || true

# --- CLI ----------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
    ok "claude $(claude --version 2>/dev/null | head -1)"
else
    note "claude not on PATH"
fi

# --- settings -----------------------------------------------------------------
if [ -f "$settings" ] && jq -e . "$settings" >/dev/null 2>&1; then
    ok "settings.json parses"
else
    bad "settings.json missing or invalid"
fi

check_setting() { # jq-path expected
    got=$(jq -r "$1 // \"<unset>\"" "$settings" 2>/dev/null || echo '<error>')
    if [ "$got" = "$2" ]; then ok "$1 = $2"; else bad "$1 = $got (expected $2)"; fi
}

check_setting '.theme' 'dark-ansi'
check_setting '.statusLine.type' 'command'
check_setting '.permissions.defaultMode' 'acceptEdits'

if jq -e 'has("skipDangerousModePermissionPrompt")' "$settings" >/dev/null 2>&1; then
    bad "skipDangerousModePermissionPrompt is still set; the permissions block replaces it"
else
    ok "skipDangerousModePermissionPrompt removed"
fi

for k in allow deny ask; do
    n=$(jq -r ".permissions.$k | length" "$settings" 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] && ok "permissions.$k has $n rules" || bad "permissions.$k is empty"
done

# CLI-owned keys must have survived the merge.
if jq -e 'has("enabledPlugins")' "$settings" >/dev/null 2>&1; then
    ok "enabledPlugins preserved through merge"
else
    note "enabledPlugins absent (fine if no plugins are installed)"
fi

# --- installed files ----------------------------------------------------------
[ -f "$claude_dir/CLAUDE.md" ] && ok "CLAUDE.md installed" || bad "CLAUDE.md missing"
[ -x "$claude_dir/statusline.sh" ] && ok "statusline.sh installed and executable" \
    || bad "statusline.sh missing or not executable"
[ -e "$claude_dir/statusline-command.sh" ] \
    && note "superseded statusline-command.sh still present" \
    || ok "superseded statusline-command.sh gone"

for f in "$repo_dir"/claude/hooks/*.sh; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -x "$claude_dir/hooks/$b" ]; then ok "hook $b"; else bad "hook $b missing"; fi
done

for f in "$repo_dir"/claude/output-styles/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    [ -f "$claude_dir/output-styles/$b" ] && ok "output style $b" || bad "output style $b missing"
done

# --- statusline behaviour -----------------------------------------------------
payload='{"workspace":{"current_dir":"'"$repo_dir"'"},"model":{"display_name":"Test"},"context_window":{"used_percentage":42.5},"cost":{"total_cost_usd":0.5,"total_duration_ms":60000,"total_lines_added":3,"total_lines_removed":1}}'

err=$(mktemp); out=$(printf '%s' "$payload" | "$claude_dir/statusline.sh" 2>"$err" || true)
if [ -n "$out" ] && [ "$(printf '%s' "$out" | wc -l)" -eq 0 ]; then
    ok "statusline emits exactly one line"
else
    bad "statusline output malformed"
fi
[ -s "$err" ] && bad "statusline wrote to stderr: $(head -1 "$err")" || ok "statusline stderr clean"
rm -f "$err"

# fail-open
out=$(printf 'not json' | "$claude_dir/statusline.sh" 2>/dev/null || true)
[ -n "$out" ] && ok "statusline fails open on bad input" || bad "statusline emits nothing on bad input"

# --- hook behaviour -----------------------------------------------------------
hp='{"session_id":"doctor","cwd":"'"$repo_dir"'","tool_input":{"file_path":"/nonexistent/x.py"}}'
for h in format-edited session-context finish-check; do
    if [ -x "$claude_dir/hooks/$h.sh" ]; then
        if printf '%s' "$hp" | "$claude_dir/hooks/$h.sh" >/dev/null 2>&1; then
            ok "hook $h exits 0"
        else
            bad "hook $h exited non-zero"
        fi
        printf 'garbage' | "$claude_dir/hooks/$h.sh" >/dev/null 2>&1 \
            && ok "hook $h fails open" || bad "hook $h fails closed on bad input"
    fi
done
rm -f "${TMPDIR:-/tmp}/claude-session-edits/doctor"

# --- skills -------------------------------------------------------------------
for d in "$repo_dir"/claude/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    f="$claude_dir/skills/$name/SKILL.md"
    if [ ! -f "$f" ]; then bad "skill $name not installed"; continue; fi
    head -1 "$f" | grep -q '^---$' || { bad "skill $name: no frontmatter"; continue; }
    grep -q '^name:' "$f" && grep -q '^description:' "$f" \
        && ok "skill $name" || bad "skill $name: frontmatter missing name/description"
done

for a in "$repo_dir"/claude/agents/*.md; do
    [ -e "$a" ] || continue
    b=$(basename "$a")
    f="$claude_dir/agents/$b"
    if [ -f "$f" ] && grep -q '^name:' "$f" && grep -q '^description:' "$f"; then
        ok "agent $b"
    else
        bad "agent $b missing or lacks frontmatter"
    fi
done

# --- duplicate skills ---------------------------------------------------------
for name in pdf docx pptx xlsx; do
    local_skill="$claude_dir/skills/$name"
    synced=$(find "$claude_dir/skills/synced" -maxdepth 2 -type d -name "$name" 2>/dev/null | head -1)
    if [ -d "$local_skill" ] && [ -n "$synced" ]; then
        bad "$name exists both locally and synced (duplicate in skill index)"
    else
        ok "$name not duplicated"
    fi
done

# --- the synced tree must be untouched ----------------------------------------
if find "$repo_dir" -path '*/skills/synced/*' -print -quit 2>/dev/null | grep -q .; then
    bad "repo contains a path under skills/synced"
else
    ok "repo owns nothing under skills/synced"
fi

# --- plugins / marketplaces ---------------------------------------------------
km="$claude_dir/plugins/known_marketplaces.json"
if [ -f "$km" ] && jq -e 'has("ecc")' "$km" >/dev/null 2>&1; then
    note "ecc marketplace still registered (claude plugin marketplace remove ecc)"
else
    ok "ecc marketplace not registered"
fi

if jq -e '.enabledPlugins["telegram@claude-plugins-official"] == true' "$settings" >/dev/null 2>&1; then
    note "telegram plugin still enabled (its MCP server needs bun, which is not installed)"
else
    ok "telegram plugin not enabled"
fi

# --- appearance prerequisites -------------------------------------------------
if command -v fc-list >/dev/null 2>&1; then
    if fc-list 2>/dev/null | grep -qi 'nerd'; then
        ok "a Nerd Font is installed (statusline glyphs will render)"
    else
        note "no Nerd Font found; statusline separators may render as tofu"
    fi
fi

if [ -f "$HOME/.config/alacritty/colors.toml" ]; then
    ok "alacritty colors.toml present (dark-ansi follows it)"
else
    note "no alacritty colors.toml; dark-ansi will follow whatever palette the terminal has"
fi

# --- secrets hygiene ----------------------------------------------------------
if [ -f "$HOME/.claude.json" ]; then
    mode=$(stat -c '%a' "$HOME/.claude.json" 2>/dev/null || echo '?')
    [ "$mode" = "600" ] && ok "~/.claude.json is 600" || bad "~/.claude.json is $mode, expected 600"
fi

echo
if [ "$fail" -ne 0 ]; then
    echo "FAILED"
    exit 1
fi
printf 'All checks passed'
[ "$warn" -gt 0 ] && printf ' (%s warning(s))' "$warn"
printf '\n'
