# Official Agent Statusline Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `@superpowers:subagent-driven-development` (recommended) or `@superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Claude Code renderers consume the current official stdin schema accurately, update Codex native status-line and hooks configuration to the current official contract, and preserve existing fallback behavior.

**Architecture:** Normalize official and legacy Claude fields once in each platform script, then let the existing segment and width-budget layers consume normalized values. Prefer Claude stdin rate-limit values and only use the current cache/OAuth path when they are absent. Keep Codex native footer configuration separate from the existing tmux renderer, migrate only project-managed values, and document the two data paths.

**Tech Stack:** Bash, PowerShell, Python `unittest`, jq, TOML-like config editing already used by `install.sh`, Markdown.

---

## File map

- `scripts/statusline.sh`: normalize official Claude fields, add opt-in session/mode/cache/cost/PR segments, and make stdin rate limits win over the external usage fallback.
- `scripts/statusline.ps1`: implement the same normalized fields, segments, precedence, and width behavior for Windows.
- `install.sh`: update the managed Codex native item list, preserve user-defined status-line lists, write canonical `[features].hooks`, and remove only managed legacy/current values.
- `tests/test_statusline.py`: add red/green coverage for official Claude payloads, API bypass/fallback, optional segments, Codex migration, and canonical hooks.
- `README.md`, `docs/claude-code.md`, `docs/codex-cli.md`: explain official schema fields, configuration boundaries, fallback behavior, and `/hooks` trust review with links to primary documentation.

### Task 1: Add failing regression tests for the official Claude contract

**Files:**
- Modify: `tests/test_statusline.py` (Claude Bash/PowerShell fixtures and Codex install assertions)

- [ ] **Step 1: Add an official Claude payload fixture.** Use non-empty, distinct `workspace.current_dir` and legacy `cwd`; encode official `rate_limits.*.resets_at` as Unix epoch seconds, `used_percentage` as numeric percentages, `prompt_cache.hit_ratio` as a 0..1 fraction, and include `thinking.enabled` alongside `fast_mode` so `mode` can cover `fast` and `think`.

- [ ] **Step 2: Add failing Bash tests.** Assert that `workspace.current_dir` wins over `cwd`, `context_window.used_percentage` wins over token arithmetic, native five/seven-day percentages and epoch reset labels are rendered, and explicit `session,mode,cache,cost,pr` renders `session:<name>`, `fast` or `think`, `cache 91%`, `$0.42`, and `PR#1234 pending`.

- [ ] **Step 3: Add fallback tests.** Cover malformed JSON, null/expired/invalid native windows, and independent fallback (native 5h remains while only missing 7d reads cache/API). Assert valid cache wins before API, timeout/401/429/offline paths remain non-blocking, and no invalid value is rendered as a fake `0%`.

- [ ] **Step 4: Add PowerShell parity tests guarded by `pwsh` availability.** Use the same fixture, optional-segment labels, official percentage precedence, and a narrow-width/long emoji session case where PowerShell is installed; otherwise keep the test skipped.

- [ ] **Step 5: Add failing Codex installer tests.** Assert the exact managed list `model-with-reasoning,current-dir,git-branch,branch-changes,context-remaining,five-hour-limit,weekly-limit,approval-mode,fast-mode,task-progress`; preserve custom single/multiline arrays; migrate only exact old/new managed arrays; set `status_line_use_colors = true` only when absent (preserve user `false`/`true`); write canonical `features.hooks = true`, remove the deprecated alias when it is the project-managed `true`, and leave unrelated feature values untouched.

- [ ] **Step 6: Run the focused tests and verify they fail for the missing behavior.**

Run: `python3 -m unittest tests.test_statusline.StatusLineTests.test_official_claude_schema_prefers_workspace_and_native_rate_limits tests.test_statusline.StatusLineTests.test_install_script_codex_native_migrates_managed_list_and_adds_color_flag`

Expected: the new assertions fail before implementation; the existing baseline assertions remain green.

### Task 2: Implement official Claude normalization and opt-in segments in Bash

**Files:**
- Modify: `scripts/statusline.sh` (input parsing, rate-limit selection, segment registry, width helpers)

- [ ] **Step 1: Normalize official fields with explicit precedence.** Parse `.workspace.current_dir // .cwd`, `.model.display_name // .model.id`, `.effort.level`, `.context_window.used_percentage`, `.session_name`, `.fast_mode`, `.thinking.enabled`, `.prompt_cache.hit_ratio`, `.cost.total_cost_usd`, `.pr.number`, and `.pr.review_state`; treat null/NaN/non-finite values as missing and keep legacy token/effort fallbacks.

- [ ] **Step 2: Parse native `rate_limits` independently of the external usage cache.** Validate each `.rate_limits.five_hour|seven_day.used_percentage` and epoch `.resets_at` separately. Preserve each valid native window, use a valid cache/API value only for a missing window, and do not call OAuth when both native windows are valid.

- [ ] **Step 3: Add `session`, `mode`, `cache`, `cost`, and `pr` builders.** Add their names to the known registry but not `default_segment_order_csv`, so they render only when explicitly listed. Map `fast_mode=true` to `fast`, `thinking.enabled=true` to `think`, otherwise a valid effort level to `effort:<level>`; map `hit_ratio` to a rounded percentage, finite USD to `$%.2f`, and PR number/state with state omission when absent. Reuse existing middle truncation and ANSI-aware width budgeting.

- [ ] **Step 4: Keep width detection compatible with the official runtime.** Prefer the explicit project max-width setting, then `COLUMNS`, then the existing safe fallback; add a test proving a supplied `COLUMNS` value is honored without invoking `tput`.

- [ ] **Step 5: Run the focused Bash tests and fix only the minimal implementation issues until green.** Commit the completed Bash/test slice before starting PowerShell.

Run: `python3 -m unittest tests.test_statusline.StatusLineTests`

Expected: all existing Claude tests plus the new official-schema tests pass.

### Task 3: Mirror the Bash behavior in PowerShell

**Files:**
- Modify: `scripts/statusline.ps1` (JSON normalization, rate-limit selection, segment builders/registry)

- [ ] **Step 1: Add PowerShell normalized properties with the same precedence and null/number validation as Bash.** Use `workspace.current_dir` before `cwd`, `used_percentage` before arithmetic, and preserve existing context/effort fallbacks.

- [ ] **Step 2: Prefer stdin rate-limit windows and gate the existing usage fallback exactly as in Bash.** Keep offline/invalid data non-blocking and visually explicit.

- [ ] **Step 3: Implement the five opt-in segment builders and feed them through the existing ordered segment and width logic.** Match Bash labels and omission rules closely enough that the same fixture produces the same semantic state.

- [ ] **Step 4: Run the PowerShell-focused tests when `pwsh` exists and run a syntax check.**

Run: `pwsh -NoProfile -Command "\$tokens=\$null; \$errors=\$null; [System.Management.Automation.Language.Parser]::ParseFile('scripts/statusline.ps1',[ref]\$tokens,[ref]\$errors) | Out-Null; if (\$errors.Count -gt 0) { \$errors | Format-List; exit 1 }"`

Expected: parser exits successfully; parity tests pass or are skipped only because `pwsh` is unavailable.

### Task 4: Update Codex native status-line and hooks migration

**Files:**
- Modify: `install.sh` (managed constants, TOML key read/write helpers, install/uninstall paths)
- Modify: `tests/test_statusline.py` (installer fixtures/assertions)

- [ ] **Step 1: Replace the stale managed item list with the exact current official identifiers.** Use `model-with-reasoning`, `current-dir`, `git-branch`, `branch-changes`, `context-remaining`, `five-hour-limit`, `weekly-limit`, `approval-mode`, `fast-mode`, and `task-progress`; do not add a command item.

- [ ] **Step 2: Make migration idempotent and non-destructive.** Read the single-line or common multiline TOML array as text, replace only absent/empty or exact old/new project-managed arrays, preserve comments and any other user-defined list, set `status_line_use_colors = true` only when absent, and remove only a project-managed `true` value during uninstall while preserving user `false`/`true` values.

- [ ] **Step 3: Switch hook enablement to canonical `[features].hooks = true`.** If `hooks` is absent or is the project-managed `true`, write one canonical key; remove the legacy `codex_hooks = true` only when present as the project alias, preserve unrelated feature keys, and remove only exact managed values during uninstall.

- [ ] **Step 4: Run focused installer tests, inspect generated TOML, and make them green.**

Run: `python3 -m unittest tests.test_statusline.StatusLineTests.test_install_script_codex_native_migrates_managed_list_and_adds_color_flag tests.test_statusline.StatusLineTests.test_install_script_codex_native_preserves_custom_status_line tests.test_statusline.StatusLineTests.test_install_script_codex_hooks_migrates_deprecated_feature_key`

Expected: custom configuration remains intact, managed migration is repeatable, and canonical hooks assertions pass.

### Task 5: Document the official contracts and verify the branch

**Files:**
- Modify: `README.md`
- Modify: `docs/claude-code.md`
- Modify: `docs/codex-cli.md`

- [ ] **Step 1: Document Claude field precedence and opt-in segments.** Explain official stdin paths, rate-limit/API fallback, `COLUMNS`, and null/invalid handling; link to the official Claude status-line page.

- [ ] **Step 2: Document Codex native versus tmux paths.** List the supported native item names, custom-list preservation, canonical hooks key, `/hooks` review/trust behavior, and official OpenAI links.

- [ ] **Step 3: Run all verification commands.**

Run: `python3 -m unittest tests/test_statusline.py`

Run: `bash -n scripts/statusline.sh scripts/codex_statusline.sh install.sh`

Run: `printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./scripts/statusline.sh`

Run: the PowerShell parser/smoke commands from Task 3 when `pwsh` is available.

Expected: the full suite passes (with only environment-appropriate skips), shell syntax is clean, and the smoke output is non-empty.

- [ ] **Step 4: Commit each completed task as a focused change, then review the final diff.**

Run: `git diff --check && git status --short && git diff --stat`

Commit message: `✨ feat: 适配官方 Claude 与 Codex 状态栏契约`
