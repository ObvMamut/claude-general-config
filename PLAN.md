# Supercharged Claude Code

> **Status:** executed 2026-09-17. `./install.sh` applied, `./doctor.sh` passes with
> zero warnings, plugin changes made. This file is kept as the design record; the
> living reference is `README.md`, and the reasoning is in `docs/decisions.md`.
>
> To change the setup, use the `claude-config` skill: edit the repo, `./install.sh`,
> `./doctor.sh`, restart Claude Code, commit. Never edit `~/.claude` directly.
>
> Deviations from the plan as written, all discovered during execution:
> - `doctor.sh` originally invoked the statusline with `sh`; it is a bash script, so
>   the checks now execute it via its shebang.
> - `install.sh` expands `$HOME` into the installed `settings.json` rather than
>   trusting the CLI to run the command strings through a shell.
> - `git status --porcelain` marks an unstaged edit with a *leading space*, so the
>   statusline and both git-reading hooks match by exclusion, not by a leading
>   non-space character. This bug was in all three scripts.

## Context

Claude Code 2.1.274, 248 startups, heavy daily use across four workloads: software
engineering, financial/market research, BAC school work, and scientific writing.
Despite that volume, the global configuration is nearly empty:

| Surface | State today |
|---|---|
| `~/.claude/CLAUDE.md` | **missing** — no global instructions at all |
| `~/.claude/agents/` | empty |
| `~/.claude/commands/` | empty |
| `~/.claude/output-styles/` | empty |
| `hooks` in settings.json | none |
| `permissions` in settings.json | none, plus `skipDangerousModePermissionPrompt: true` |
| `~/.claude/skills/` | 34 skills, **all** scientific/finance; zero software-engineering |
| Statusline | works, but two scripts exist and one (`statusline.sh`) is dead |
| Plugins | 4 installed; `telegram` fails to load (`bun` not in `$PATH`) |
| ECC marketplace | registered, never installed |
| `pdf`/`docx`/`pptx`/`xlsx` | installed **twice** (local K-Dense + cloud-synced), duplicated in the skill index |

Meanwhile `~/all/programming/supercharged-codex` is a well-built, versioned,
reproducible configuration repo for Codex — `install.sh`, `doctor.sh`, pinned
lockfiles, backups, an explicit scope boundary. This project builds the Claude Code
counterpart in the same house style, in the empty
`~/all/programming/claude-general-purpose`.

**Outcome:** one `./install.sh` reproduces the entire Claude Code setup on any
machine; `./doctor.sh` proves it is intact; every change is reviewable in git and
reversible from a backup.

### Decisions already made

- Versioned repo, **copy-based** install (not symlinks), mirroring supercharged-codex.
- Tuned for all four workloads.
- Boundary: **strict on money** (no paid/metered APIs, no new credentials), **relaxed
  on automation** (hooks are fine).
- Appearance: statusline, theme colors, output styles, terminal polish.
- ECC: **skip and deregister**.
- Permissions: **curated allowlist** replaces blanket bypass.
- Hooks: quality-gate + session-context only. No safety-guard hook (deny rules cover
  it), no notification/telegram work.
- Coding capability: **official plugins + a few bespoke skills**, not a vendored
  awesome-copilot mirror.

---

## Repo layout

```
~/all/programming/claude-general-purpose/
├── README.md               # what this is, install, scope boundary
├── CLAUDE.md               # repo's own working notes (not the installed one)
├── install.sh              # backup → merge → copy → report
├── doctor.sh               # validate everything install.sh claims
├── .gitignore              # secrets.env, .install-backups/
├── claude/
│   ├── CLAUDE.md           # → ~/.claude/CLAUDE.md   (global instructions)
│   ├── settings.json       # managed keys only, merged via jq
│   ├── statusline.sh       # → ~/.claude/statusline.sh
│   ├── output-styles/      # → ~/.claude/output-styles/
│   ├── agents/             # → ~/.claude/agents/
│   ├── skills/             # → ~/.claude/skills/<name>/
│   └── hooks/              # → ~/.claude/hooks/
├── terminal/
│   └── alacritty-snippet.toml  # documented, NOT auto-applied
└── docs/
    └── decisions.md        # why ECC is out, why ansi theme, etc.
```

`install.sh` follows the supercharged-codex pattern: timestamped backups into
`.install-backups/<date>/`, copy managed files, print what moved. Never touches
`.credentials.json` or `~/.claude.json`.

**One deviation from the Codex installer, and it matters:** `~/.claude/settings.json`
is written by the CLI itself (`enabledPlugins`, `extraKnownMarketplaces` change when
you run `/plugin`). A blind `cp` would silently revert plugin changes. So install.sh
**merges** our managed keys with `jq`, preserving CLI-owned keys:

```sh
jq -s '.[0] * .[1]' "$claude_dir/settings.json" "$repo_dir/claude/settings.json" > "$tmp"
```

`claude/settings.json` therefore contains only keys we own: `theme`, `statusLine`,
`outputStyle`, `permissions`, `hooks`, `terminalTitle`, `cleanupPeriodDays`,
`effortLevel`, `model`, `tui`.

---

## A. Appearance

### A1. Theme — inherit the chroma palette

`theme` accepts only 6 built-in values (verified against the 2.1.274 binary:
`dark`, `light`, and their `-daltonized` / `-ansi` variants). There is no custom-theme
support. But `dark-ansi` renders through the **terminal's** 16 ANSI colors, and
`~/.config/alacritty/colors.toml` is generated by your own `chroma` tool from the
current wallpaper.

**Change `theme` from `"dark"` to `"dark-ansi"`.** Claude Code then re-themes itself
every time chroma regenerates the palette — a real custom theme, with zero maintenance
and no edits to a file whose header says *"do not edit by hand."*

This one decision sets the rule for everything else visual below: **use ANSI color
indices (0–15), never hex.** Anything hardcoded would drift out of sync on the next
wallpaper change.

### A2. Statusline rebuild

`claude/statusline.sh` replaces `statusline-command.sh`. Styled to match your p10k
prompt (`POWERLEVEL9K_MODE=nerdfont-v3`, powerline, classic, darkest) — nerd-font
glyphs and powerline separators, 2772 nerd-font faces already installed.

Segments, all from fields verified present in the 2.1.274 statusline payload:

| Segment | Source | Notes |
|---|---|---|
| dir | `workspace.current_dir` | `~`-shortened, truncated to last 2 components |
| git | `git -C` | branch + dirty marker + ahead/behind |
| model | `model.display_name` | |
| effort | `settings.json` → `effortLevel` | not in payload; read from disk, cached |
| output style | `output_style` | hidden when `default` |
| context | `context_window.used_percentage` | color ramp; `exceeds_200k_tokens` → warning glyph |
| diff | `cost.total_lines_added` / `removed` | `+N/-N`, hidden at zero |
| cost | `cost.total_cost_usd` + `total_duration_ms` | |

Implementation rules, learned from the two scripts being replaced:
- Single `jq` invocation parsing all fields at once — the current script spawns `jq` 5×
  per render, on every keystroke.
- Integer-guard every numeric comparison. The dead `statusline.sh` does
  `[ "$PCT" -gt 70 ]` on a float, which errors on every render.
- Hard timeout on the git call so a slow/NFS repo can never stall the UI.
- Fail-open: any error prints a minimal line rather than nothing.

### A3. Output styles

Three styles in `claude/output-styles/`, selectable with `/output-style`:

- **`terse`** — minimal prose, code and diffs first. For engineering sessions.
- **`research-report`** — structured findings, explicit sourcing, numbers with units
  and as-of dates, assumptions called out. For financial and scientific work.
- **`tutor`** — works a problem stepwise, checks understanding before advancing,
  refuses to hand over the final answer first. For BAC revision.

`outputStyle` default stays unset (standard behavior); you opt in per session.

### A4. Terminal polish

- `terminalTitle` enabled so Alacritty tabs show the active task.
- `terminal/alacritty-snippet.toml` documents the optional additions (window title,
  scrollback) — **printed by the installer, never applied automatically.** Your
  Alacritty config is small and hand-maintained; the repo does not own it.
- `doctor.sh` verifies a nerd font resolves, so the statusline never renders as tofu.

---

## B. Global instructions

`claude/CLAUDE.md` → `~/.claude/CLAUDE.md`. Currently missing entirely; this is the
highest-leverage single file in the project.

Ported from your `supercharged-codex/AGENTS.md` (root-cause over suppression, smallest
cohesive change, validate in proportion to risk, never claim an unrun check passed,
per-language toolchain commands), plus Claude-Code-specific sections that Codex has no
equivalent for:

- **Skill discipline** — with superpowers at 419 uses and `brainstorming` at 45, the
  workflow is already load-bearing. Write down when brainstorming vs. systematic-debugging
  leads, and that process skills precede implementation skills.
- **Workload routing** — finance → `fred-economic-data` / `alpha-vantage` / `edgartools`;
  school → the synced `philo-lessons` / `bac-revision-sheets`; writing → `scientific-writing`
  + `citation-management`. Prevents the 34-skill index from being searched blind.
- **The money boundary**, stated explicitly: no paid API, metered service, or new
  credential without an explicit request in the current task.
- **Verification** — evidence before assertions, mirroring `superpowers:verification-before-completion`.

Reuses the existing `superpowers` skills by reference rather than restating them.

---

## C. Permissions

Replaces `skipDangerousModePermissionPrompt: true` + no allowlist. Today that is
maximum blast radius with zero guardrails; the swap is strictly safer *and* quieter.

```jsonc
"permissions": {
  "defaultMode": "acceptEdits",
  "allow": [ /* read-only shell + your toolchain */ ],
  "deny":  [ /* destructive ops + secret files */ ],
  "ask":   [ /* network-mutating, publishing */ ]
}
```

- **allow** — `git status/log/diff/show/branch`, `rg`, `fd`, `ls`, `cat`, `bat`, `eza`,
  `head`/`tail`/`wc`, and the toolchains present on this box: `uv`, `python3`, `npm`,
  `node`, `cargo`, `gh` (read subcommands only).
- **deny** — `rm -rf` outside the scratchpad, `git push --force` to `main`/`master`,
  and reads of `~/.claude/.credentials.json`, `~/.claude.json`, `~/.ssh/**`, `**/.env*`.
- **ask** — `git push`, `gh pr create`, `gh release`, package publish.

Built by running the `/fewer-permission-prompts` skill against your transcripts so the
allowlist reflects commands you actually run, not guesses.

`defaultMode: "acceptEdits"` keeps file edits friction-free (closest to how you work
today) while restoring a prompt on unrecognized shell commands. **Judgment call worth
flipping** — `"default"` is stricter if the prompts turn out to be tolerable.

Note: `~/.claude.json` currently holds `GEMINI_API_KEY` in plaintext. The deny rule
stops Claude reading it; `install.sh` additionally checks the file is `600` and warns
if not. Relocating the key to a gitignored `secrets.env` sourced via the `env` setting
is offered as a follow-up, not done silently.

---

## D. Hooks

Three hooks in `claude/hooks/`, all POSIX `sh`, all **fail-open** (a broken hook must
never wedge a session) and all with a hard timeout.

### D1. `format-edited.sh` — PostToolUse on `Edit|Write|MultiEdit`
Dispatches on file extension to a formatter **only when** the tool is installed *and*
the project already uses it (config file present): `ruff format` / `rustfmt` /
`prettier` / `gofmt`. Silent on success, never reformats files the project doesn't
manage, never installs anything.

### D2. `session-context.sh` — SessionStart
Injects a compact block: branch, dirty-file count, last 3 commits, and any root
`TODO.md`. Capped at ~20 lines, skipped entirely outside a git repo. Budget: <200ms.

### D3. `finish-check.sh` — Stop
**Advisory only, never blocking.** In a git repo with uncommitted changes, emits a
one-line reminder of what is unstaged. Deliberately does not attempt to detect failing
tests — that is `superpowers:verification-before-completion`'s job, and a hook guessing
at it would produce false alarms.

---

## E. Skills, plugins, agents

### E1. Plugins — enable

| Plugin | Why |
|---|---|
| `context7` | Up-to-date library docs. Your Codex `AGENTS.md` already mandates Context7; Claude Code has no equivalent. Free tier, no credential. |
| `plugin-dev` | Authoring toolkit for the hooks/skills/settings this repo ships. |
| `github` | PR and issue management; `gh` is already installed at `~/.local/bin/gh`. |

**Deliberately not enabled:** `code-review`, `code-simplifier`, and `security-guidance`
duplicate the built-in `/code-review`, `/simplify`, and `/security-review` skills you
already have. Adding them would put two competing implementations in the index.

### E2. Plugins — disable / deregister
- `telegram` — MCP server fails (`bun` not in `$PATH`) and notifications are out of
  scope. Disable rather than install a runtime for an unused feature.
- `ecc` marketplace — deregistered. 246 third-party skills would swamp skill selection,
  and its README's "182K+ stars / Anthropic Hackathon Winner" claims do not hold up.
- `rust-analyzer-lsp` — keep as-is.

### E3. Bespoke skills

Four skills in `claude/skills/`, chosen to fill gaps that neither the 34 scientific
skills, the superpowers plugin, nor the built-ins cover:

- **`repo-onboarding`** — ported from supercharged-codex. Structured first pass over an
  unfamiliar repo. No Claude Code equivalent exists.
- **`dependency-evaluation`** — ported from supercharged-codex. Assess a new dependency
  before adding it.
- **`market-data-workflow`** — chains `fred-economic-data` → `alpha-vantage` →
  `edgartools` (your three most-used skills: 34 + 28 + 8 invocations) with shared
  conventions for caching, free-tier rate limits, and as-of dating. Today each is
  invoked cold with no shared protocol.
- **`claude-config`** — maintains *this* repo: add a skill, edit a managed setting,
  re-run install and doctor. Makes the setup self-servicing.

Each gets frontmatter with a trigger-focused `description`, validated by the synced
`anthropic-skills:skill-creator`.

### E4. Agents

Two subagents in `claude/agents/`, both avoiding overlap with the built-in `Explore`,
`Plan`, and `general-purpose`:

- **`market-analyst`** — read-only, scoped to the finance skills and data tools, for
  fanning out a research question without polluting the main context.
- **`skill-auditor`** — reviews a skill's frontmatter and body against the
  skill-creator rules; used by `doctor.sh` and when adding skills.

### E5. Cleanup

- Delete `~/.claude/statusline.sh` — orphaned, unreferenced, and broken (float
  comparison with `-gt`).
- Remove the local K-Dense `pdf`, `docx`, `pptx`, `xlsx` from `~/.claude/skills/`;
  the cloud-synced copies in `~/.claude/skills/synced/` supersede them and are
  Anthropic-maintained. Removes 4 duplicate entries from the skill index.
- Set `cleanupPeriodDays` — `~/.claude` is at 279MB.

**`~/.claude/skills/synced/` is never touched by this repo.** It is account-synced from
claude.ai (`philo-lessons`, `portfolio-manager`, `swing-trade-analyst`,
`bac-revision-sheets`, `morning`, `skill-creator`, …); anything written there would be
overwritten by the next sync. `doctor.sh` asserts the repo owns no path under it.

---

## Critical files

| Path | Action |
|---|---|
| `~/all/programming/claude-general-purpose/` | `git init`; all new files |
| `~/.claude/settings.json` | **merged** via jq, not overwritten |
| `~/.claude/CLAUDE.md` | created (currently missing) |
| `~/.claude/statusline.sh` | replaces `statusline-command.sh` |
| `~/.claude/{output-styles,agents,hooks}/` | created, populated |
| `~/.claude/skills/{4 bespoke}/` | created |
| `~/.claude/skills/{pdf,docx,pptx,xlsx}/` | removed (duplicates) |
| `~/.config/alacritty/*` | **not modified** — snippet documented only |
| `~/.claude/skills/synced/**` | **not modified** — cloud-owned |

Reference implementations to follow: `supercharged-codex/install.sh` (backup +
idempotent copy), `supercharged-codex/doctor.sh` (validate-or-exit-1),
`supercharged-codex/AGENTS.md` (instruction voice and scope boundary).

---

## Build order

1. `git init`, README, `.gitignore`, skeleton dirs.
2. `claude/CLAUDE.md` — highest leverage, ship first.
3. `install.sh` with jq-merge + backups; `doctor.sh` alongside it.
4. Statusline + `dark-ansi` theme.
5. Output styles.
6. Permissions block (via `/fewer-permission-prompts`).
7. Hooks, one at a time, each verified before the next.
8. Plugin enable/disable, ECC deregistration, duplicate-skill cleanup.
9. Bespoke skills, then agents.
10. `docs/decisions.md`; commit.

---

## Verification

`./doctor.sh` must exit 0, asserting:

- `claude --version` runs; `settings.json` parses and every managed key holds its
  expected value.
- `theme == "dark-ansi"`; a nerd font resolves via `fc-list`.
- Statusline: feed it a recorded JSON payload on stdin and assert it emits one line,
  non-empty, under 200ms, with no `jq`/arithmetic errors on stderr. Re-run with a
  malformed payload to prove fail-open.
- Each hook: run directly with a sample payload, assert exit 0 and a bounded runtime.
  Then `disableAllHooks` off and confirm a live session still starts.
- Every skill in `claude/skills/` and agent in `claude/agents/` passes frontmatter
  validation.
- `pdf`/`docx`/`pptx`/`xlsx` appear exactly once in the merged skill index.
- `ecc` absent from `known_marketplaces.json`; `telegram` disabled.
- No repo-managed path resolves under `~/.claude/skills/synced/`.
- `~/.claude.json` is mode 600.

End-to-end, by hand after `./install.sh` and a restart:

1. Start a session — statusline renders with glyphs and correct colors; SessionStart
   context block appears.
2. Change wallpaper so chroma regenerates `colors.toml`; reopen Claude Code and confirm
   it re-themed with the terminal.
3. Edit a Python file in a ruff project — confirm it formats, and that a file in a
   non-ruff project is left alone.
4. Run an allowlisted command (no prompt), a denied one (blocked), an `ask` one (prompts).
5. `/output-style tutor`, ask a BAC question, confirm stepwise behavior and that the
   statusline shows the active style.
6. Finish with uncommitted changes — confirm the Stop hook's advisory line, and that it
   does not block.
7. Re-run `./install.sh` — idempotent, no spurious diff in `~/.claude/settings.json`.

---

## Out of scope

Notifications and telegram (disabled, not fixed); ECC; scheduled/cron agents and `/loop`
routines; any paid or metered API; relocating `GEMINI_API_KEY` (offered, not done);
`~/.config/alacritty/*` edits; `~/.claude/skills/synced/`; the 34 existing K-Dense
skills, apart from the 4 duplicate removals.
