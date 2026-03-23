# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AICodingStatusLine is a custom status line for Claude Code and Codex CLI that displays model info, git context, token usage, and rate limits. It is a fork of [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine). The project consists of two parallel Claude Code scripts (`statusline.sh` for Bash, `statusline.ps1` for PowerShell) that must stay feature-aligned, plus a separate `codex_statusline.sh` for Codex CLI (Bash-only, tmux-based).

## Commands

```bash
# Run full test suite
python3 -m unittest tests/test_statusline.py

# Run a single test
python3 -m unittest tests.test_statusline.StatusLineTests.test_wide_budget_keeps_all_segments

# Smoke-test Bash script
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./scripts/statusline.sh

# Smoke-test PowerShell script
pwsh -NoProfile -File ./scripts/statusline.ps1 < sample.json

# Smoke-test Codex status line
CODEX_MODEL_NAME=gpt-5.4 ./scripts/codex_statusline.sh /path/to/project
```

There is no build pipeline, linter, or formatter. Scripts are edited directly.

## Architecture

Both Claude Code scripts follow the same pipeline: **read JSON from stdin -> parse model/context/cwd data -> fetch usage from Anthropic API (with 60s cache at `/tmp/claude/statusline-usage-cache.json`) -> compose segments -> adaptive width truncation -> output ANSI-colored text**.

### Codex CLI Status Line

`codex_statusline.sh` is a standalone Bash script for Codex CLI. It follows a different data pipeline: **read model/effort from `~/.codex/config.toml` -> find latest session JSONL in `~/.codex/sessions/` -> parse last `token_count` event (with 10s cache at `/tmp/codex/statusline-session-cache.json`) -> compose segments -> adaptive width truncation -> output ANSI-colored text**. It shares the same theme system, layout system, and width-adaptive rendering as `statusline.sh` but has no PowerShell counterpart (Codex CLI is macOS/Linux + tmux only). It does not have an `extra` segment (Codex provides no extra usage data). Environment variables use the `CODEX_STATUSLINE_` prefix instead of `CLAUDE_CODE_STATUSLINE_`.

### Dual-Script Parity (Claude Code)

`statusline.sh` (Bash) and `statusline.ps1` (PowerShell) implement identical logic. Changes to one must be mirrored in the other. The PowerShell script must remain ASCII-only (non-ASCII glyphs are built from code points like `[char]0x25CF` instead of source literals).

### Segment Composition

Segments are built independently (`build_model_segment`, `build_git_segment`, `build_ctx_segment`, `build_eff_segment`, `build_five_hour_segment`, `build_seven_day_segment`, `build_extra_segment`) then joined with `|` separators. Each segment produces both a `TEXT` (ANSI-colored) and `PLAIN` (uncolored) variant; `PLAIN` is used for width calculations.

### Width Budget System

When output exceeds `max_width`, segments collapse in a fixed priority order:
1. Drop `extra` segment
2. Drop 7-day reset time
3. Drop 5-hour reset time
4. Drop git diff stats
5. Drop 7-day segment entirely
6. Truncate git segment with `...` ellipsis

### Layouts and Configuration

- `CLAUDE_CODE_STATUSLINE_LAYOUT`: `bars` (default, overview line + two progress-bar lines for 5h/7d) or `compact` (single-line)
- `CLAUDE_CODE_STATUSLINE_BAR_STYLE`: `ascii` (default), `dots`, `squares` -- only affects `bars` layout
- `CLAUDE_CODE_STATUSLINE_THEME`: `default` or `forest` -- changes ANSI color palette
- `CLAUDE_CODE_STATUSLINE_MAX_WIDTH`: force a specific width budget

## Coding Conventions

- **Bash**: 4-space indent, `snake_case` functions, `UPPERCASE` env vars
- **PowerShell**: 4-space indent, `Verb-Noun` PascalCase functions (e.g., `Format-Tokens`, `Build-GitSegment`)
- **Tests**: Python `unittest` with `test_*` methods; tests invoke the actual shell scripts via `subprocess`

## Testing

Tests in `tests/test_statusline.py` exercise both scripts by piping JSON stdin and checking stripped-ANSI output. They set up temporary git repos, write usage cache files, and validate width budgeting, layout modes, theme isolation, bar style glyphs, and Bash/PowerShell parity. Run the test suite before any PR that touches layout, truncation, or theme logic.

## Plugin System

The project is a Claude Code plugin with `.claude-plugin/plugin.json` (plugin manifest) and `.claude-plugin/marketplace.json` (marketplace registry). Key points:

- **plugin.json**: Must use valid lifecycle events for hooks (e.g., `SessionStart`, `PostToolUse`). There is no `postInstall` event — use `SessionStart` with idempotent scripts instead.
- **marketplace.json**: The `source` field inside `plugins[]` uses `"source": "url"` (not `"type": "url"`). Top-level `description` is not a valid field.
- **Validation**: Run `claude plugin validate .` before committing plugin manifest changes.
- **post-install.sh**: Runs as `SessionStart` hook. Must be idempotent — uses `cmp` file comparison and stamp file to skip on subsequent sessions.

## GitHub Release Workflow

```bash
# 1. Update version in .claude-plugin/plugin.json
# 2. Run tests
python3 tests/test_statusline.py

# 3. Commit, push
git push origin main

# 4. Create release (GITHUB_TOKEN env var has no scopes — must unset it to use keyring token)
GITHUB_TOKEN="" gh release create v<VERSION> --repo kaelinda/AICodingStatusLine --title "v<VERSION>" --notes "..."
```

Note: The `GITHUB_TOKEN` environment variable (set by Claude Code session) has no scopes. To create releases, unset it so `gh` falls back to the keyring token which has `repo` scope.

## Commit Style

Use short Conventional Commit subjects with emoji prefixes: `feat:`, `fix:`, `docs:`, etc.

<!-- chinese-language-config:start -->
## Language
Use **Chinese** for:
- Task execution results and error messages
- Confirmations and clarifications with the user
- Solution descriptions and to-do items
- Commit info for git
<!-- chinese-language-config:end -->
