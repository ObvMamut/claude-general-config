---
name: claude-config
description: Change this machine's Claude Code setup — settings, statusline, hooks, output styles, skills, agents, plugins. Use whenever a change to ~/.claude is requested, so the change goes through the versioned repo instead of being edited in place and lost on the next install.
---

# Claude Config

The Claude Code setup on this machine is generated from a git repository at
`~/all/programming/claude-general-purpose`. `~/.claude` is **output**, not source.

## The rule

Edit the repo, then run `./install.sh`. Never edit a managed file under `~/.claude`
directly — the next install overwrites it and the change is lost with no trace.

Managed by the repo:

| Repo path | Installs to |
|---|---|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/settings.json` | merged into `~/.claude/settings.json` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |
| `claude/hooks/*.sh` | `~/.claude/hooks/` |
| `claude/output-styles/*.md` | `~/.claude/output-styles/` |
| `claude/agents/*.md` | `~/.claude/agents/` |
| `claude/skills/*/` | `~/.claude/skills/` |

Not managed, and not to be written by the repo or by hand:

- `~/.claude/skills/synced/**` — synced from the claude.ai account. Writes there are
  lost at the next sync.
- `~/.claude.json` and `~/.claude/.credentials.json` — CLI state and secrets.
- Keys in `settings.json` the CLI owns (`enabledPlugins`, `extraKnownMarketplaces`).
  This is why install.sh **merges** that file with `jq` instead of copying it.

## Workflow

1. Edit the relevant file under `claude/` in the repo.
2. `./install.sh` — backs up whatever it replaces into `.install-backups/<timestamp>/`.
3. `./doctor.sh` — must exit 0.
4. Restart Claude Code. Settings, hooks, skills, and output styles are read at startup.
5. Commit. The point of the repo is that every change to the setup is reviewable.

## Adding things

- **Skill** → `claude/skills/<name>/SKILL.md` with `name` and `description` frontmatter.
  The description is what drives triggering: describe *when to use it*, not what it is.
- **Hook** → a POSIX `sh` script in `claude/hooks/`, plus an entry in
  `claude/settings.json`. Every hook must exit 0 on every path, hold a timeout, and
  fail open. A hook that can fail closed can wedge every session on this machine.
- **Output style** → `claude/output-styles/<name>.md` with `name` and `description`.
- **Plugin** → not a repo file. Use `claude plugin install|disable`, then note it in
  `docs/decisions.md` so the choice is not re-litigated later.

## Before changing the statusline

It renders on a keystroke cadence. Keep it to one `jq` process, keep colours as ANSI
palette indices 0-15 (never hex, so the line follows whatever palette `chroma` has
generated), integer-guard every numeric comparison, and keep the git call hard-timeouted.
Test with `doctor.sh`, which feeds it a recorded payload plus a malformed one.

## Rollback

Every install writes `.install-backups/<timestamp>/` mirroring the paths it replaced.
To undo, copy the files back and re-run `doctor.sh`.
