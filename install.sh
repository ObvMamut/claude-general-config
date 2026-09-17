#!/bin/sh
# Install this repository's Claude Code configuration into ~/.claude.
#
# Safe to re-run. Every file it replaces is backed up first, under
# .install-backups/<timestamp>/ mirroring its path inside ~/.claude.
#
# NEVER touched:
#   ~/.claude/.credentials.json   authentication
#   ~/.claude.json                CLI state, and it holds secrets
#   ~/.claude/skills/synced/**    synced from claude.ai; writes there are lost
#
# settings.json is MERGED, not copied: the CLI owns keys in that file
# (enabledPlugins, extraKnownMarketplaces) that a blind copy would revert.

set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
claude_dir=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
backup_root="$repo_dir/.install-backups/$(date +%Y%m%d-%H%M%S)"
backed_up=0

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

say() { printf '  %s\n' "$*"; }

backup() {
    target=$1
    [ -e "$target" ] || return 0
    rel=${target#"$claude_dir"/}
    dest="$backup_root/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -R "$target" "$dest"
    backed_up=1
}

install_file() {
    src=$1 dst=$2
    backup "$dst"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

# Refuse to run if the repo would write anywhere under skills/synced.
case "$repo_dir" in
    *"/skills/synced"*) echo "refusing: repo sits inside skills/synced" >&2; exit 1 ;;
esac

mkdir -p "$claude_dir/output-styles" "$claude_dir/agents" "$claude_dir/hooks" "$claude_dir/skills"

echo "Installing into $claude_dir"

# --- global instructions ------------------------------------------------------
install_file "$repo_dir/claude/CLAUDE.md" "$claude_dir/CLAUDE.md"
say "CLAUDE.md"

# --- statusline ---------------------------------------------------------------
install_file "$repo_dir/claude/statusline.sh" "$claude_dir/statusline.sh"
chmod +x "$claude_dir/statusline.sh"
say "statusline.sh"

# --- hooks --------------------------------------------------------------------
for f in "$repo_dir"/claude/hooks/*.sh; do
    [ -e "$f" ] || continue
    install_file "$f" "$claude_dir/hooks/$(basename "$f")"
    chmod +x "$claude_dir/hooks/$(basename "$f")"
done
say "hooks/"

# --- output styles ------------------------------------------------------------
for f in "$repo_dir"/claude/output-styles/*.md; do
    [ -e "$f" ] || continue
    install_file "$f" "$claude_dir/output-styles/$(basename "$f")"
done
say "output-styles/"

# --- agents -------------------------------------------------------------------
for f in "$repo_dir"/claude/agents/*.md; do
    [ -e "$f" ] || continue
    install_file "$f" "$claude_dir/agents/$(basename "$f")"
done
say "agents/"

# --- skills -------------------------------------------------------------------
for d in "$repo_dir"/claude/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    backup "$claude_dir/skills/$name"
    rm -rf "$claude_dir/skills/$name"
    cp -R "$d" "$claude_dir/skills/$name"
done
say "skills/"

# --- settings.json: merge, never overwrite ------------------------------------
settings="$claude_dir/settings.json"
backup "$settings"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp=$(mktemp)
# Our keys win; every other existing key is preserved. skipDangerousModePermissionPrompt
# is explicitly dropped: the permissions block replaces it.
jq -s '.[0] * .[1] | del(.skipDangerousModePermissionPrompt)' \
    "$settings" "$repo_dir/claude/settings.json" > "$tmp"
jq -e . "$tmp" >/dev/null || { echo "merged settings.json is not valid JSON" >&2; rm -f "$tmp"; exit 1; }

# The repo stores commands with a literal $HOME so it stays portable. Expand it
# here rather than relying on the CLI to run these through a shell.
tmp2=$(mktemp)
jq --arg home "$HOME" '
    (.statusLine.command) |= (. // "" | gsub("\\$HOME"; $home))
  | (.hooks[]?[]?.hooks[]?.command) |= (. // "" | gsub("\\$HOME"; $home))
' "$tmp" > "$tmp2"
jq -e . "$tmp2" >/dev/null || { echo "settings.json invalid after \$HOME expansion" >&2; rm -f "$tmp" "$tmp2"; exit 1; }
rm -f "$tmp"
mv "$tmp2" "$settings"
say "settings.json (merged)"

# --- retire superseded files --------------------------------------------------
if [ -e "$claude_dir/statusline-command.sh" ]; then
    backup "$claude_dir/statusline-command.sh"
    rm -f "$claude_dir/statusline-command.sh"
    say "removed superseded statusline-command.sh"
fi

# Local copies of skills that the claude.ai sync also provides. The synced copy
# is authoritative; keeping both puts duplicates in the skill index.
for name in pdf docx pptx xlsx; do
    local_skill="$claude_dir/skills/$name"
    synced=$(find "$claude_dir/skills/synced" -maxdepth 2 -type d -name "$name" 2>/dev/null | head -1)
    if [ -d "$local_skill" ] && [ ! -L "$local_skill" ] && [ -n "$synced" ]; then
        backup "$local_skill"
        rm -rf "$local_skill"
        say "removed duplicate local skill: $name (synced copy kept)"
    fi
done

# --- report -------------------------------------------------------------------
echo
if [ "$backed_up" -eq 1 ]; then
    echo "Backed up replaced files in $backup_root"
fi

if [ -f "$HOME/.claude.json" ]; then
    mode=$(stat -c '%a' "$HOME/.claude.json" 2>/dev/null || echo '?')
    [ "$mode" = "600" ] || echo "WARNING: ~/.claude.json is mode $mode, expected 600 (it holds secrets)"
fi

cat <<'EOF'

Not done automatically — run these yourself if you want them:
  claude plugin disable telegram@claude-plugins-official
  claude plugin marketplace remove ecc
  claude plugin install context7@claude-plugins-official
  claude plugin install plugin-dev@claude-plugins-official
  claude plugin install github@claude-plugins-official

Optional Alacritty additions are documented in terminal/alacritty-snippet.toml.
They are NOT applied: your Alacritty config is hand-maintained.

Restart Claude Code to pick up settings, hooks, skills, and output styles.
EOF
