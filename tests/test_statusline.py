import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHELL_SCRIPT = ROOT / "scripts" / "statusline.sh"
PS_SCRIPT = ROOT / "scripts" / "statusline.ps1"
INSTALL_SCRIPT = ROOT / "install.sh"
TMUX_LAUNCHER_SCRIPT = ROOT / "scripts" / "codex_tmux.sh"
TMUX_STATUS_SCRIPT = ROOT / "scripts" / "codex_tmux_status.sh"
CODEX_SCRIPT = ROOT / "scripts" / "codex_statusline.sh"
HOOK_SIDECAR_SCRIPT = ROOT / "scripts" / "codex_hook_sidecar.sh"
NOTIFY_BRIDGE_SCRIPT = ROOT / "scripts" / "codex_notify_bridge.sh"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
DOTS_BAR_RE = r"[\u25cf\u25cb]+"
DEFAULT_SECONDARY_ANSI = "[38;2;133;149;155m"
DRACULA_SECONDARY_ANSI = "[38;2;132;145;182m"
DEFAULT_7D_TIME = "03/06 08:00"
DEFAULT_7D_SHORT_DATE = "03/06"
CUSTOM_7D_TIME = "99-03-06 08:00"
CODEX_2W_TIME = "3/25 0:00 reset"
CODEX_2W_SHORT_DATE = "3/25"
CUSTOM_CODEX_2W_TIME = "26-03-25 00:00"
CODEX_5H_LEFT = 86
CODEX_WEEKLY_LEFT = 96
CODEX_TMUX_LAUNCHER_NAME = "codex-tmux"
CODEX_TMUX_STATUS_NAME = "codex-tmux-status"
CODEX_STATUSLINE_NAME = "codex-statusline"
CODEX_STATUSLINE_COMMON_NAME = "codex-statusline-common.sh"
CODEX_HOOK_SIDECAR_NAME = "codex-hook-sidecar"
CODEX_NOTIFY_BRIDGE_NAME = "codex-notify-bridge"

# Simulated Codex session JSONL token_count event
CODEX_TOKEN_COUNT_EVENT = {
    "timestamp": "2026-03-11T09:50:50.021Z",
    "type": "event_msg",
    "payload": {
        "type": "token_count",
        "info": {
            "total_token_usage": {
                "input_tokens": 87288,
                "cached_input_tokens": 57728,
                "output_tokens": 1569,
                "reasoning_output_tokens": 640,
                "total_tokens": 88857,
            },
            "model_context_window": 258400,
        },
        "rate_limits": {
            "primary": {
                "used_percent": 14.0,
                "window_minutes": 300,
                "resets_at": 4102444800,
            },
            "secondary": {
                "used_percent": 4.0,
                "window_minutes": 20161,
                "resets_at": 1774396800,
            },
            "credits": None,
            "plan_type": "plus",
        },
    },
}

CODEX_TOKEN_COUNT_EVENT_WITH_LAST_USAGE = {
    "timestamp": "2026-03-13T03:19:14.442Z",
    "type": "event_msg",
    "payload": {
        "type": "token_count",
        "info": {
            "total_token_usage": {
                "input_tokens": 8523974,
                "cached_input_tokens": 7543552,
                "output_tokens": 23658,
                "reasoning_output_tokens": 5371,
                "total_tokens": 8547632,
            },
            "last_token_usage": {
                "input_tokens": 128588,
                "cached_input_tokens": 5504,
                "output_tokens": 728,
                "reasoning_output_tokens": 185,
                "total_tokens": 129316,
            },
            "model_context_window": 258400,
        },
        "rate_limits": {
            "primary": {
                "used_percent": 1.0,
                "window_minutes": 300,
                "resets_at": 1773387265,
            },
            "secondary": {
                "used_percent": 13.0,
                "window_minutes": 10080,
                "resets_at": 1773876842,
            },
            "credits": {
                "has_credits": False,
                "unlimited": False,
                "balance": None,
            },
            "plan_type": None,
        },
    },
}

CODEX_TOKEN_COUNT_NULL_LIMITS = {
    "timestamp": "2026-03-11T09:50:50.021Z",
    "type": "event_msg",
    "payload": {
        "type": "token_count",
        "info": {
            "total_token_usage": {
                "input_tokens": 50000,
                "cached_input_tokens": 30000,
                "output_tokens": 1000,
                "reasoning_output_tokens": 500,
                "total_tokens": 51000,
            },
            "model_context_window": 258400,
        },
        "rate_limits": {
            "primary": None,
            "secondary": None,
            "credits": None,
            "plan_type": "plus",
        },
    },
}

SAMPLE_INPUT = {
    "model": {"display_name": "Opus 4.6"},
    "context_window": {
        "context_window_size": 200000,
        "current_usage": {
            "input_tokens": 12345,
            "cache_creation_input_tokens": 1000,
            "cache_read_input_tokens": 2000,
        },
    },
}

SAMPLE_USAGE = {
    "five_hour": {"utilization": 83, "resets_at": "2099-03-11T02:00:00Z"},
    "seven_day": {"utilization": 63, "resets_at": "2099-03-06T08:00:00Z"},
    "extra_usage": {
        "is_enabled": True,
        "utilization": 12,
        "used_credits": 1234,
        "monthly_limit": 2000,
    },
}


def strip_ansi(value: str) -> str:
    return ANSI_RE.sub("", value)


class StatusLineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.clean_repo = Path(self.temp_dir.name) / "clean-repo"
        self.clean_repo.mkdir()
        subprocess.run(["git", "init"], cwd=self.clean_repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=self.clean_repo, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=self.clean_repo, check=True)
        (self.clean_repo / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "add", "tracked.txt"], cwd=self.clean_repo, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=self.clean_repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "checkout", "-b", "codex/feature/for-claude"], cwd=self.clean_repo, check=True, capture_output=True, text=True)

        self.cache_home = Path(self.temp_dir.name) / "cache-home"
        self.cache_home.mkdir(parents=True, exist_ok=True)
        self.usage_dir = Path("/tmp/claude")
        self.usage_dir.mkdir(parents=True, exist_ok=True)
        self.usage_cache = self.usage_dir / "statusline-usage-cache.json"
        self.original_cache = None
        if self.usage_cache.exists():
            self.original_cache = self.usage_cache.read_text()
        self.addCleanup(self._restore_cache)

    def _restore_cache(self) -> None:
        if self.original_cache is None:
            try:
                self.usage_cache.unlink()
            except FileNotFoundError:
                pass
            return
        self.usage_cache.write_text(self.original_cache)

    def _write_usage(self, payload) -> None:
        self.usage_cache.write_text(json.dumps(payload))

    def _run_shell(self, budget=None, usage=True, cwd=None, raw=False, extra_env=None, layout="compact"):
        env = os.environ.copy()
        env["HOME"] = str(self.cache_home)
        env["TZ"] = "UTC"
        env["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
        for key in list(env):
            if key.startswith("CLAUDE_CODE_STATUSLINE_"):
                del env[key]
        if layout is not None:
            env["CLAUDE_CODE_STATUSLINE_LAYOUT"] = layout
        if budget is not None:
            env["CLAUDE_CODE_STATUSLINE_MAX_WIDTH"] = str(budget)
        if extra_env:
            env.update(extra_env)

        if usage is True:
            self._write_usage(SAMPLE_USAGE)
        elif usage is False:
            try:
                self.usage_cache.unlink()
            except FileNotFoundError:
                pass
        else:
            self._write_usage(usage)

        payload = dict(SAMPLE_INPUT)
        payload["cwd"] = str(cwd or self.clean_repo)

        result = subprocess.run(
            ["/bin/bash", str(SHELL_SCRIPT)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )
        return result.stdout if raw else strip_ansi(result.stdout)

    def _run_install(self, *args, home=None):
        env = os.environ.copy()
        install_home = Path(home) if home is not None else Path(self.temp_dir.name) / "install-home"
        install_home.mkdir(parents=True, exist_ok=True)
        env["HOME"] = str(install_home)

        result = subprocess.run(
            ["/bin/bash", str(INSTALL_SCRIPT), *args],
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )
        return install_home, strip_ansi(result.stdout)

    def _run_tmux_status(self, cwd=None, extra_env=None, layout="compact"):
        env = os.environ.copy()
        env["HOME"] = str(self.cache_home)
        env["TZ"] = "UTC"
        env["CODEX_STATUSLINE_FORMAT"] = "ansi"  # Force ANSI in tests
        if layout is not None:
            env["CODEX_STATUSLINE_LAYOUT"] = layout
        # Isolate from real session data
        empty_sessions = Path(self.temp_dir.name) / "empty-sessions"
        empty_sessions.mkdir(exist_ok=True)
        env["CODEX_STATUSLINE_SESSION_DIR"] = str(empty_sessions)
        # Use isolated cache file
        cache = Path(self.temp_dir.name) / "tmux-codex-cache.json"
        env["CODEX_STATUSLINE_CACHE_FILE"] = str(cache)
        try:
            cache.unlink()
        except FileNotFoundError:
            pass
        if extra_env:
            env.update(extra_env)

        result = subprocess.run(
            ["/bin/bash", str(TMUX_STATUS_SCRIPT), str(cwd or self.clean_repo)],
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )
        return result.stdout.strip()

    def _run_pwsh(self, budget=None, extra_env=None):
        runtime = shutil.which("pwsh") or shutil.which("powershell")
        if runtime is None:
            self.skipTest("PowerShell runtime unavailable")

        self._write_usage(SAMPLE_USAGE)
        env = os.environ.copy()
        env["HOME"] = str(self.cache_home)
        env["USERPROFILE"] = str(self.cache_home)
        env["TZ"] = "UTC"
        env["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
        for key in list(env):
            if key.startswith("CLAUDE_CODE_STATUSLINE_"):
                del env[key]
        if budget is not None:
            env["CLAUDE_CODE_STATUSLINE_MAX_WIDTH"] = str(budget)
        if extra_env:
            env.update(extra_env)

        result = subprocess.run(
            [runtime, "-NoProfile", "-File", str(PS_SCRIPT)],
            input=json.dumps(SAMPLE_INPUT),
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )
        return strip_ansi(result.stdout)

    def test_wide_budget_keeps_all_segments(self):
        output = self._run_shell(budget=145)
        self.assertIn("Opus 4.6", output)
        self.assertIn("ctx 15k/200k 7%", output)
        self.assertIn("eff low", output)
        self.assertIn("5h 83% 2:00", output)
        self.assertIn(f"7d 63% {DEFAULT_7D_TIME}", output)
        self.assertIn("extra $12.34/$20.00", output)
        self.assertLessEqual(len(output), 145)

    def test_medium_budget_drops_extra_before_core_segments(self):
        output = self._run_shell(budget=100)
        self.assertIn("ctx 15k/200k 7%", output)
        self.assertIn("5h 83% 2:00", output)
        self.assertIn("7d 63%", output)
        self.assertNotIn("extra ", output)
        self.assertLessEqual(len(output), 100)

    def test_narrow_budget_drops_7d_and_truncates_git_segment(self):
        output = self._run_shell(budget=72)
        self.assertIn("ctx 15k/200k 7%", output)
        self.assertIn("eff low", output)
        self.assertIn("5h 83%", output)
        self.assertNotIn("7d ", output)
        self.assertNotIn("extra ", output)
        self.assertIn("...", output)
        self.assertLessEqual(len(output), 72)

    def test_no_usage_data_shows_placeholders(self):
        output = self._run_shell(budget=130, usage=False)
        self.assertIn("5h -", output)
        self.assertIn("7d -", output)
        self.assertNotIn("extra ", output)

    def test_git_diff_is_hidden_when_repo_is_clean(self):
        output = self._run_shell(budget=130)
        self.assertNotRegex(output, r"\(\+\d+ -\d+\)")

    def test_git_segment_compacts_nested_branch_name(self):
        output = self._run_shell(budget=145)
        self.assertIn("codex/.../for-claude", output)

    def test_git_segment_uses_compact_path_prefix(self):
        output = self._run_shell(budget=145)
        self.assertRegex(output, r"\.\.\./clean-repo")

    def test_git_diff_appears_when_repo_is_dirty(self):
        repo_dir = Path(self.temp_dir.name) / "dirty-repo"
        repo_dir.mkdir()
        subprocess.run(["git", "init"], cwd=repo_dir, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_dir, check=True)
        (repo_dir / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "add", "tracked.txt"], cwd=repo_dir, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=repo_dir, check=True, capture_output=True, text=True)
        (repo_dir / "tracked.txt").write_text("base\nchange\n")

        output = self._run_shell(budget=130, cwd=repo_dir)
        self.assertRegex(output, r"\(\+\d+ -\d+\)")

    def test_powershell_matches_segment_order_when_available(self):
        shell_output = self._run_shell(budget=100)
        pwsh_output = self._run_pwsh(budget=100)

        self.assertIn("ctx 15k/200k 7%", pwsh_output)
        self.assertIn("eff low", pwsh_output)
        self.assertIn("5h 83% 2:00", pwsh_output)
        self.assertIn(f"7d 63% {DEFAULT_7D_TIME}", pwsh_output)
        self.assertNotIn("extra ", pwsh_output)
        self.assertEqual(shell_output.split(" | ")[:4], pwsh_output.split(" | ")[:4])

    def test_theme_preset_changes_ansi_palette_without_changing_plain_text(self):
        default_raw = self._run_shell(budget=100, raw=True)
        forest_raw = self._run_shell(
            budget=100,
            raw=True,
            extra_env={"CLAUDE_CODE_STATUSLINE_THEME": "forest"},
        )

        self.assertIn("[38;2;77;166;255m", default_raw)
        self.assertIn("[38;2;120;196;120m", forest_raw)
        self.assertEqual(strip_ansi(default_raw), strip_ansi(forest_raw))

    def test_all_themes_produce_same_plain_text(self):
        default_plain = self._run_shell(budget=100)
        theme_accent_markers = {
            "dracula": "[38;2;189;147;249m",
            "monokai": "[38;2;102;217;239m",
            "solarized": "[38;2;38;139;210m",
            "ocean": "[38;2;0;188;212m",
            "sunset": "[38;2;255;138;101m",
            "amber": "[38;2;255;193;7m",
            "rose": "[38;2;244;143;177m",
        }
        for theme, marker in theme_accent_markers.items():
            raw = self._run_shell(
                budget=100,
                raw=True,
                extra_env={"CLAUDE_CODE_STATUSLINE_THEME": theme},
            )
            self.assertIn(marker, raw, f"Theme '{theme}' missing accent color")
            self.assertEqual(
                default_plain,
                strip_ansi(raw),
                f"Theme '{theme}' changed plain text output",
            )

    def test_unknown_layout_falls_back_to_bars(self):
        bars_output = self._run_shell(budget=100, layout="bars")
        unknown_output = self._run_shell(
            budget=100,
            layout=None,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "mystery"},
        )

        self.assertEqual(bars_output, unknown_output)

    def test_default_layout_is_bars(self):
        output = self._run_shell(budget=120, layout=None)
        lines = output.splitlines()
        self.assertEqual(3, len(lines))

    def test_powershell_script_source_is_ascii_only_for_windows_compat(self):
        script_bytes = PS_SCRIPT.read_bytes()
        self.assertTrue(all(byte < 128 for byte in script_bytes))

    def test_bars_layout_outputs_three_lines_with_usage_bars(self):
        output = self._run_shell(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()

        self.assertEqual(3, len(lines))
        self.assertIn("Opus 4.6", lines[0])
        self.assertIn("ctx 15k/200k 7%", lines[0])
        self.assertIn("eff low", lines[0])
        self.assertNotIn("5h ", lines[0])
        self.assertNotIn("7d ", lines[0])
        self.assertRegex(lines[1], r"^5h 83% \[[=\-]+\] 2:00$")
        self.assertRegex(lines[2], rf"^7d 63% \[[=\-]+\] {re.escape(DEFAULT_7D_TIME)}$")

    def test_bars_layout_narrow_width_keeps_bar_and_drops_time_first(self):
        output = self._run_shell(
            budget=44,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()

        self.assertEqual(3, len(lines))
        self.assertRegex(lines[1], r"^5h 83% \[[=\-]+\]$")
        self.assertRegex(lines[2], rf"^7d 63% \[[=\-]+\]( {re.escape(DEFAULT_7D_SHORT_DATE)})?$")
        self.assertIn("[", lines[1])
        self.assertIn("[", lines[2])

    def test_custom_seven_day_time_format_applies_in_compact_layout(self):
        output = self._run_shell(
            budget=130,
            extra_env={"CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%y-%m-%d %H:%M"},
        )

        self.assertIn(f"7d 63% {CUSTOM_7D_TIME}", output)

    def test_invalid_seven_day_time_format_falls_back_to_default(self):
        output = self._run_shell(
            budget=130,
            extra_env={"CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%q-%m"},
        )

        self.assertIn(f"7d 63% {DEFAULT_7D_TIME}", output)

    def test_bars_layout_uses_custom_seven_day_time_format(self):
        output = self._run_shell(
            budget=120,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%y-%m-%d %H:%M",
            },
        )
        lines = output.splitlines()

        self.assertRegex(lines[2], rf"^7d 63% \[[=\-]+\] {re.escape(CUSTOM_7D_TIME)}$")

    def test_bars_layout_narrow_width_uses_short_default_date_for_seven_day(self):
        output = self._run_shell(
            budget=44,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%y-%m-%d %H:%M",
            },
        )
        lines = output.splitlines()

        self.assertRegex(lines[2], rf"^7d 63% \[[=\-]+\]( {re.escape(DEFAULT_7D_SHORT_DATE)})?$")

    def test_bars_layout_without_usage_keeps_placeholders(self):
        output = self._run_shell(
            budget=120,
            usage=False,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()

        self.assertEqual(3, len(lines))
        self.assertEqual("5h -- [----------] n/a", lines[1])
        self.assertEqual("7d -- [----------] n/a", lines[2])

    def test_bars_layout_dots_style_changes_bar_glyphs(self):
        output = self._run_shell(
            budget=120,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "dots",
            },
        )
        lines = output.splitlines()

        self.assertEqual(3, len(lines))
        self.assertRegex(lines[1], rf"^5h 83% \[{DOTS_BAR_RE}\] 2:00$")
        self.assertRegex(lines[2], rf"^7d 63% \[{DOTS_BAR_RE}\] {re.escape(DEFAULT_7D_TIME)}$")
        self.assertIn("●", lines[1])
        self.assertIn("○", lines[1])

    def test_bars_layout_squares_style_keeps_placeholders(self):
        output = self._run_shell(
            budget=120,
            usage=False,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "squares",
            },
        )
        lines = output.splitlines()

        self.assertEqual(3, len(lines))
        self.assertEqual("5h -- [□□□□□□□□□□] n/a", lines[1])
        self.assertEqual("7d -- [□□□□□□□□□□] n/a", lines[2])

    def test_unknown_bar_style_falls_back_to_ascii(self):
        default_output = self._run_shell(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        unknown_output = self._run_shell(
            budget=120,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "mystery",
            },
        )

        self.assertEqual(default_output, unknown_output)

    def test_bars_layout_theme_changes_only_ansi(self):
        default_raw = self._run_shell(
            budget=120,
            raw=True,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        forest_raw = self._run_shell(
            budget=120,
            raw=True,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_THEME": "forest",
            },
        )

        self.assertIn("[38;2;77;166;255m", default_raw)
        self.assertIn("[38;2;120;196;120m", forest_raw)
        self.assertEqual(strip_ansi(default_raw), strip_ansi(forest_raw))

    def test_bars_layout_uses_accessible_secondary_palette(self):
        default_raw = self._run_shell(
            budget=120,
            raw=True,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        dracula_raw = self._run_shell(
            budget=120,
            raw=True,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_THEME": "dracula",
            },
        )

        self.assertIn(DEFAULT_SECONDARY_ANSI, default_raw)
        self.assertIn(DRACULA_SECONDARY_ANSI, dracula_raw)

    def test_powershell_bars_layout_matches_line_order_when_available(self):
        shell_output = self._run_shell(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        pwsh_output = self._run_pwsh(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )

        shell_lines = shell_output.splitlines()
        pwsh_lines = pwsh_output.splitlines()
        self.assertEqual(3, len(pwsh_lines))
        self.assertEqual(shell_lines[0], pwsh_lines[0])
        self.assertRegex(pwsh_lines[1], r"^5h 83% \[[=\-]+\] 2:00$")
        self.assertRegex(pwsh_lines[2], rf"^7d 63% \[[=\-]+\] {re.escape(DEFAULT_7D_TIME)}$")

    def test_powershell_custom_seven_day_time_format_matches_shell(self):
        shell_output = self._run_shell(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%y-%m-%d %H:%M"},
        )
        pwsh_output = self._run_pwsh(
            budget=120,
            extra_env={"CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT": "%y-%m-%d %H:%M"},
        )

        self.assertIn(f"7d 63% {CUSTOM_7D_TIME}", shell_output)
        self.assertIn(f"7d 63% {CUSTOM_7D_TIME}", pwsh_output)

    def test_powershell_bars_layout_uses_selected_bar_style_when_available(self):
        shell_output = self._run_shell(
            budget=120,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "dots",
            },
        )
        pwsh_output = self._run_pwsh(
            budget=120,
            extra_env={
                "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
                "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "dots",
            },
        )

        shell_lines = shell_output.splitlines()
        pwsh_lines = pwsh_output.splitlines()
        self.assertEqual(shell_lines[0], pwsh_lines[0])
        self.assertRegex(pwsh_lines[1], rf"^5h 83% \[{DOTS_BAR_RE}\] 2:00$")
        self.assertRegex(pwsh_lines[2], rf"^7d 63% \[{DOTS_BAR_RE}\] {re.escape(DEFAULT_7D_TIME)}$")


    def test_segments_filter_hides_model(self):
        output = self._run_shell(budget=150, extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "eff,git,ctx,5h,7d",
        })
        self.assertNotIn("Opus 4.6", output)
        self.assertIn("eff low", output)
        self.assertIn("ctx", output)

    def test_segments_filter_hides_5h_and_7d(self):
        output = self._run_shell(budget=150, extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "model,eff,git,ctx",
        })
        self.assertIn("Opus 4.6", output)
        self.assertNotIn("5h ", output)
        self.assertNotIn("7d ", output)

    def test_segments_filter_empty_shows_all(self):
        output = self._run_shell(budget=145, extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "",
        })
        self.assertIn("Opus 4.6", output)
        self.assertIn("eff low", output)
        self.assertIn("5h ", output)
        self.assertIn("7d ", output)

    def test_segments_filter_only_model(self):
        output = self._run_shell(budget=150, extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "model",
        })
        self.assertIn("Opus 4.6", output)
        self.assertNotIn("eff", output)
        self.assertNotIn("ctx", output)
        self.assertNotIn("5h", output)

    def test_segments_filter_bars_hides_5h_bar_line(self):
        output = self._run_shell(budget=120, layout="bars", extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "model,eff,git,ctx,7d",
        })
        lines = output.splitlines()
        self.assertEqual(2, len(lines))
        self.assertNotIn("5h", output)

    def test_segments_filter_bars_hides_both_bars(self):
        output = self._run_shell(budget=120, layout="bars", extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "model,eff,git,ctx",
        })
        lines = output.splitlines()
        self.assertEqual(1, len(lines))

    def test_segments_filter_with_spaces(self):
        output = self._run_shell(budget=150, extra_env={
            "CLAUDE_CODE_STATUSLINE_SEGMENTS": "model, eff, ctx",
        })
        self.assertIn("Opus 4.6", output)
        self.assertIn("eff low", output)
        self.assertIn("ctx", output)
        self.assertNotIn("5h", output)

    def test_past_reset_time_is_hidden(self):
        past_usage = {
            "five_hour": {"utilization": 83, "resets_at": "2020-01-01T02:00:00Z"},
            "seven_day": {"utilization": 63, "resets_at": "2020-01-01T08:00:00Z"},
            "extra_usage": {"is_enabled": False},
        }
        output = self._run_shell(budget=145, usage=past_usage)
        self.assertIn("5h 83%", output)
        self.assertNotRegex(output, r"5h 83% \d")
        self.assertIn("7d 63%", output)
        self.assertNotRegex(output, r"7d 63% \d")

    def test_bars_layout_past_reset_time_is_hidden(self):
        past_usage = {
            "five_hour": {"utilization": 83, "resets_at": "2020-01-01T02:00:00Z"},
            "seven_day": {"utilization": 63, "resets_at": "2020-01-01T08:00:00Z"},
            "extra_usage": {"is_enabled": False},
        }
        output = self._run_shell(
            budget=120,
            usage=past_usage,
            extra_env={"CLAUDE_CODE_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()
        self.assertEqual(3, len(lines))
        self.assertRegex(lines[1], r"^5h 83% \[[=\-]+\]$")
        self.assertRegex(lines[2], r"^7d 63% \[[=\-]+\]$")

    def test_install_script_codex_target_installs_tmux_assets(self):
        install_home, _ = self._run_install("--target", "codex")

        self.assertTrue((install_home / ".codex" / "bin" / CODEX_TMUX_LAUNCHER_NAME).exists())
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_TMUX_STATUS_NAME).exists())
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_STATUSLINE_NAME).exists())
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_STATUSLINE_COMMON_NAME).exists())
        self.assertFalse((install_home / ".claude" / "statusline.sh").exists())

    def test_install_script_codex_target_installs_dynamic_bars_tmux_launcher(self):
        install_home, _ = self._run_install("--target", "codex")
        launcher_text = (install_home / ".codex" / "bin" / CODEX_TMUX_LAUNCHER_NAME).read_text()

        self.assertIn('tmux set-option -t "$session_name" -q status-left ""', launcher_text)
        self.assertIn('CODEX_STATUSLINE_SHOW_GIT_LINE', launcher_text)
        self.assertIn('CODEX_STATUSLINE_SHOW_OVERVIEW_LINE', launcher_text)
        self.assertIn('visible_lines=()', launcher_text)
        self.assertIn('tmux set-option -t "$session_name" -q status "${#visible_lines[@]}"', launcher_text)
        self.assertIn('tmux set-option -t "$session_name" -q "status-format[$idx]" "  #($status_base --line ${visible_lines[$idx]})"', launcher_text)

    def test_install_script_codex_native_target_writes_tui_status_line(self):
        install_home, _ = self._run_install("--target", "codex-native")

        config_text = (install_home / ".codex" / "config.toml").read_text()
        self.assertIn("[tui]", config_text)
        self.assertIn('status_line = ["model-with-reasoning", "context-remaining", "current-dir"]', config_text)
        self.assertFalse((install_home / ".codex" / "bin" / CODEX_TMUX_LAUNCHER_NAME).exists())

    def test_install_script_uninstall_removes_tmux_assets(self):
        install_home, _ = self._run_install("--target", "codex")
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_TMUX_LAUNCHER_NAME).exists())
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_TMUX_STATUS_NAME).exists())
        self.assertTrue((install_home / ".codex" / "bin" / CODEX_STATUSLINE_NAME).exists())

        self._run_install("--uninstall", home=install_home)

        self.assertFalse((install_home / ".codex" / "bin" / CODEX_TMUX_LAUNCHER_NAME).exists())
        self.assertFalse((install_home / ".codex" / "bin" / CODEX_TMUX_STATUS_NAME).exists())
        self.assertFalse((install_home / ".codex" / "bin" / CODEX_STATUSLINE_NAME).exists())

    def test_install_script_uninstall_removes_native_tui_status_line(self):
        install_home, _ = self._run_install("--target", "codex-native")
        config_file = install_home / ".codex" / "config.toml"
        self.assertIn('status_line = ["model-with-reasoning", "context-remaining", "current-dir"]', config_file.read_text())

        self._run_install("--uninstall", home=install_home)

        self.assertNotIn('status_line = ["model-with-reasoning", "context-remaining", "current-dir"]', config_file.read_text())

    def test_tmux_status_script_renders_local_summary(self):
        """codex_tmux_status.sh shim now delegates to codex_statusline.sh."""
        output = self._run_tmux_status()
        stripped = strip_ansi(output)

        self.assertIn("eff med", stripped)
        self.assertIn("ctx 0/0 0%", stripped)
        self.assertIn("git ", stripped)
        self.assertIn("for-claude", stripped)

    def test_tmux_status_script_includes_model_when_available(self):
        output = self._run_tmux_status(extra_env={"CODEX_MODEL_NAME": "gpt-5.1-codex"})
        stripped = strip_ansi(output)

        self.assertIn("gpt-5.1-codex", stripped)
        self.assertIn("git codex/feature/for-claude", stripped)

    def test_tmux_status_script_shows_git_diff_for_dirty_repo(self):
        repo_dir = Path(self.temp_dir.name) / "dirty-repo-tmux"
        repo_dir.mkdir()
        subprocess.run(["git", "init"], cwd=repo_dir, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_dir, check=True)
        (repo_dir / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "add", "tracked.txt"], cwd=repo_dir, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=repo_dir, check=True, capture_output=True, text=True)
        (repo_dir / "tracked.txt").write_text("base\nchange\n")

        output = self._run_tmux_status(cwd=repo_dir)
        stripped = strip_ansi(output)

        self.assertRegex(stripped, r"\(\+\d+ -\d+\)")

    def test_readme_documents_tmux_launcher(self):
        readme_text = (ROOT / "README.md").read_text()

        self.assertIn("codex-tmux", readme_text)
        self.assertIn("tmux", readme_text.lower())
        self.assertIn("codex_statusline", readme_text.lower())

    def test_install_script_codex_with_hooks_installs_hook_sidecar_and_hooks_json(self):
        install_home, _ = self._run_install("--target", "codex", "--with-hooks")

        hook_script = install_home / ".codex" / "bin" / CODEX_HOOK_SIDECAR_NAME
        hooks_json = json.loads((install_home / ".codex" / "hooks.json").read_text())
        config_text = (install_home / ".codex" / "config.toml").read_text()

        self.assertTrue(hook_script.exists())
        self.assertIn("SessionStart", hooks_json["hooks"])
        self.assertIn("PreToolUse", hooks_json["hooks"])
        self.assertIn("PostToolUse", hooks_json["hooks"])
        self.assertIn(str(hook_script), json.dumps(hooks_json))
        self.assertIn("[features]", config_text)
        self.assertIn("codex_hooks = true", config_text)
        self.assertIn("show_hook_segment = true", config_text)

    def test_install_script_codex_native_with_notify_installs_notify_bridge_and_config(self):
        install_home, _ = self._run_install("--target", "codex-native", "--with-notify")

        notify_script = install_home / ".codex" / "bin" / CODEX_NOTIFY_BRIDGE_NAME
        config_text = (install_home / ".codex" / "config.toml").read_text()

        self.assertTrue(notify_script.exists())
        self.assertIn(f'notify = ["{notify_script}"]', config_text)
        self.assertIn("[tui]", config_text)
        self.assertIn("notifications = true", config_text)

    def test_install_script_codex_with_notify_enables_notify_segment_for_tmux(self):
        install_home, _ = self._run_install("--target", "codex", "--with-notify")

        config_text = (install_home / ".codex" / "config.toml").read_text()

        self.assertIn('notify = ["', config_text)
        self.assertIn("show_notify_segment = true", config_text)

    def test_install_script_uninstall_removes_hook_sidecar_and_hooks_json_entries(self):
        install_home, _ = self._run_install("--target", "codex", "--with-hooks")
        hook_script = install_home / ".codex" / "bin" / CODEX_HOOK_SIDECAR_NAME
        hooks_file = install_home / ".codex" / "hooks.json"

        self._run_install("--uninstall", home=install_home)

        self.assertFalse(hook_script.exists())
        if hooks_file.exists():
            self.assertNotIn(CODEX_HOOK_SIDECAR_NAME, hooks_file.read_text())

    def test_install_script_uninstall_removes_notify_bridge_and_notify_settings(self):
        install_home, _ = self._run_install("--target", "codex-native", "--with-notify")
        notify_script = install_home / ".codex" / "bin" / CODEX_NOTIFY_BRIDGE_NAME
        config_file = install_home / ".codex" / "config.toml"

        self._run_install("--uninstall", home=install_home)

        self.assertFalse(notify_script.exists())
        config_text = config_file.read_text()
        self.assertNotIn(CODEX_NOTIFY_BRIDGE_NAME, config_text)
        self.assertNotIn("notifications = true", config_text)

    def test_codex_docs_note_native_status_line_and_experimental_hooks(self):
        readme_text = (ROOT / "README.md").read_text()
        codex_doc_text = (ROOT / "docs" / "codex-cli.md").read_text()

        self.assertIn("tui.status_line", readme_text)
        self.assertIn("实验性 hooks", readme_text)
        self.assertIn("--with-notify", readme_text)
        self.assertIn("codex-native", codex_doc_text)
        self.assertIn("tui.status_line", codex_doc_text)
        self.assertIn("codex_hooks = true", codex_doc_text)
        self.assertIn("notify =", codex_doc_text)
        self.assertIn("git pull --ff-only", codex_doc_text)
        self.assertIn("show_notify_segment", codex_doc_text)


class CodexStatusLineTests(unittest.TestCase):
    """Tests for codex_statusline.sh — Codex CLI status line."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

        # Create temporary git repo
        self.repo = Path(self.temp_dir.name) / "codex-repo"
        self.repo.mkdir()
        subprocess.run(["git", "init"], cwd=self.repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=self.repo, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=self.repo, check=True)
        (self.repo / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "add", "tracked.txt"], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=self.repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "checkout", "-b", "feat/codex-test"], cwd=self.repo, check=True, capture_output=True, text=True)

        # Create mock ~/.codex/config.toml
        self.codex_home = Path(self.temp_dir.name) / ".codex"
        self.codex_home.mkdir()
        (self.codex_home / "config.toml").write_text(
            'model = "gpt-5.4"\nmodel_reasoning_effort = "high"\n'
        )

        # Create mock session JSONL
        self.session_dir = self.codex_home / "sessions" / "2026" / "03" / "11"
        self.session_dir.mkdir(parents=True)

    def _write_session(self, events=None):
        """Write session JSONL file with given events (default: standard token_count)."""
        if events is None:
            events = [CODEX_TOKEN_COUNT_EVENT]
        session_file = self.session_dir / "rollout-test.jsonl"
        lines = [json.dumps(e) for e in events]
        session_file.write_text("\n".join(lines) + "\n")

    def _write_codex_config(self, extra_statusline=None):
        config_text = 'model = "gpt-5.4"\nmodel_reasoning_effort = "high"\n'
        if extra_statusline:
            config_text += "\n[statusline]\n" + extra_statusline
            if not config_text.endswith("\n"):
                config_text += "\n"
        (self.codex_home / "config.toml").write_text(config_text)

    def _run_codex(self, budget=None, extra_env=None, raw=False, write_session=True, cwd=None, args=None, layout="compact"):
        env = os.environ.copy()
        env["HOME"] = str(Path(self.temp_dir.name))
        env["TZ"] = "UTC"
        env["CODEX_STATUSLINE_SESSION_DIR"] = str(self.codex_home / "sessions")
        env["CODEX_STATUSLINE_FORMAT"] = "ansi"  # Force ANSI in tests (not tmux)
        # Use isolated cache file per test to avoid interference from real sessions
        cache = Path(self.temp_dir.name) / "codex-cache.json"
        env["CODEX_STATUSLINE_CACHE_FILE"] = str(cache)
        # Clear any existing env overrides
        codex_keep = {"CODEX_STATUSLINE_SESSION_DIR", "CODEX_STATUSLINE_FORMAT", "CODEX_STATUSLINE_CACHE_FILE"}
        for key in list(env):
            if key.startswith("CODEX_STATUSLINE_") or key.startswith("CODEX_MODEL") or key.startswith("CODEX_EFFORT"):
                if key not in codex_keep:
                    del env[key]
        # Clear test cache
        try:
            cache.unlink()
        except FileNotFoundError:
            pass
        if layout is not None:
            env["CODEX_STATUSLINE_LAYOUT"] = layout
        if budget is not None:
            env["CODEX_STATUSLINE_MAX_WIDTH"] = str(budget)
        if extra_env:
            env.update(extra_env)
        if write_session:
            self._write_session()

        cmd = ["/bin/bash", str(CODEX_SCRIPT), str(cwd or self.repo)]
        if args:
            cmd.extend(args)

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )
        return result.stdout if raw else strip_ansi(result.stdout)

    def _run_codex_tmux_launcher(self, extra_env=None, cwd=None, config_statusline=None):
        fake_bin = Path(self.temp_dir.name) / "fake-bin"
        fake_bin.mkdir(exist_ok=True)
        tmux_log = Path(self.temp_dir.name) / "tmux-launcher.log"
        tmux_script = fake_bin / "tmux"
        tmux_script.write_text(
            "#!/bin/bash\n"
            "for arg in \"$@\"; do printf '%s\\t' \"$arg\"; done >> \"$TMUX_LOG\"\n"
            "printf '\\n' >> \"$TMUX_LOG\"\n"
            "exit 0\n"
        )
        tmux_script.chmod(0o755)

        if config_statusline is not None:
            self._write_codex_config(config_statusline)

        env = os.environ.copy()
        env["HOME"] = str(Path(self.temp_dir.name))
        env["PATH"] = f"{fake_bin}:{env['PATH']}"
        env["TMUX_LOG"] = str(tmux_log)
        env["CODEX_TMUX_STATUS_SCRIPT"] = str(CODEX_SCRIPT)
        if extra_env:
            env.update(extra_env)

        subprocess.run(
            ["/bin/bash", str(TMUX_LAUNCHER_SCRIPT)],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(cwd or self.repo),
            check=True,
        )

        return tmux_log.read_text().splitlines()

    def _run_hook_sidecar(self, payload):
        cache = Path(self.temp_dir.name) / "hook-cache.json"
        env = os.environ.copy()
        env["CODEX_STATUSLINE_HOOK_CACHE_FILE"] = str(cache)

        subprocess.run(
            ["/bin/bash", str(HOOK_SIDECAR_SCRIPT)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )

        return json.loads(cache.read_text())

    def _run_notify_bridge(self, payload=None, args=None):
        cache = Path(self.temp_dir.name) / "notify-cache.json"
        env = os.environ.copy()
        env["CODEX_NOTIFY_BRIDGE_CACHE_FILE"] = str(cache)
        env["CODEX_NOTIFY_BRIDGE_DISABLE_DESKTOP"] = "1"

        subprocess.run(
            ["/bin/bash", str(NOTIFY_BRIDGE_SCRIPT), *(args or [])],
            input="" if payload is None else json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
            cwd=ROOT,
            check=True,
        )

        return json.loads(cache.read_text())

    def test_codex_model_from_config(self):
        output = self._run_codex(budget=150)
        self.assertIn("gpt-5.4", output)

    def test_codex_model_env_override(self):
        output = self._run_codex(budget=150, extra_env={"CODEX_MODEL_NAME": "o3"})
        self.assertIn("o3", output)
        self.assertNotIn("gpt-5.4", output)

    def test_codex_effort_display(self):
        output = self._run_codex(budget=150)
        self.assertIn("eff high", output)

    def test_codex_effort_env_override(self):
        output = self._run_codex(budget=150, extra_env={"CODEX_EFFORT_LEVEL": "low"})
        self.assertIn("eff low", output)

    def test_codex_ctx_segment(self):
        output = self._run_codex(budget=150)
        self.assertIn("ctx 89k/258k 34%", output)

    def test_codex_ctx_prefers_last_token_usage_when_available(self):
        self._write_session([CODEX_TOKEN_COUNT_EVENT_WITH_LAST_USAGE])
        output = self._run_codex(budget=150, write_session=False)

        self.assertIn("ctx 129k/258k 50%", output)
        self.assertNotIn("ctx 8.5m/258k", output)

    def test_codex_hook_sidecar_records_pretooluse_status(self):
        state = self._run_hook_sidecar({
            "hookEventName": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": "npm test"},
        })

        self.assertEqual("PreToolUse", state["hook_event_name"])
        self.assertEqual("bash run", state["summary"])
        self.assertEqual("npm test", state["command_preview"])

    def test_codex_hook_sidecar_marks_posttooluse_failure_from_exit_code(self):
        state = self._run_hook_sidecar({
            "hookEventName": "PostToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": "npm test"},
            "tool_response": "{\"exit_code\":1}",
        })

        self.assertEqual("PostToolUse", state["hook_event_name"])
        self.assertEqual("bash fail", state["summary"])
        self.assertEqual("1", state["exit_code"])

    def test_codex_hook_segment_reads_recent_hook_cache(self):
        hook_cache = Path(self.temp_dir.name) / "hook-cache.json"
        hook_cache.write_text(json.dumps({
            "hook_event_name": "PostToolUse",
            "summary": "bash ok",
            "updated_at": 1773350000,
        }))

        output = self._run_codex(
            budget=180,
            extra_env={
                "CODEX_STATUSLINE_SHOW_HOOK_SEGMENT": "true",
                "CODEX_STATUSLINE_HOOK_CACHE_FILE": str(hook_cache),
                "CODEX_STATUSLINE_NOW_EPOCH": "1773350100",
            },
        )

        self.assertIn("hook bash ok", output)

    def test_codex_notify_bridge_records_json_payload_from_stdin(self):
        state = self._run_notify_bridge({
            "title": "Codex",
            "message": "Waiting for your approval",
            "level": "info",
        })

        self.assertEqual("Codex", state["title"])
        self.assertEqual("Waiting for your approval", state["message"])
        self.assertEqual("info", state["level"])
        self.assertEqual("Waiting for your approval", state["summary"])

    def test_codex_notify_bridge_accepts_payload_from_first_argument(self):
        state = self._run_notify_bridge(
            args=[json.dumps({
                "title": "Codex",
                "message": "Task finished",
                "status": "success",
            })]
        )

        self.assertEqual("Codex", state["title"])
        self.assertEqual("Task finished", state["message"])
        self.assertEqual("success", state["level"])
        self.assertEqual("Task finished", state["summary"])

    def test_codex_notify_segment_reads_recent_notify_cache(self):
        notify_cache = Path(self.temp_dir.name) / "notify-cache.json"
        notify_cache.write_text(json.dumps({
            "summary": "Waiting for approval",
            "updated_at": 1773350000,
        }))

        output = self._run_codex(
            budget=180,
            extra_env={
                "CODEX_STATUSLINE_SHOW_NOTIFY_SEGMENT": "true",
                "CODEX_STATUSLINE_NOTIFY_CACHE_FILE": str(notify_cache),
                "CODEX_STATUSLINE_NOW_EPOCH": "1773350100",
            },
        )

        self.assertIn("notify Waiting for approval", output)

    def test_codex_segments_filter_can_hide_notify_segment(self):
        notify_cache = Path(self.temp_dir.name) / "notify-cache.json"
        notify_cache.write_text(json.dumps({
            "summary": "Waiting for approval",
            "updated_at": 1773350000,
        }))

        output = self._run_codex(
            budget=180,
            extra_env={
                "CODEX_STATUSLINE_SHOW_NOTIFY_SEGMENT": "true",
                "CODEX_STATUSLINE_NOTIFY_CACHE_FILE": str(notify_cache),
                "CODEX_STATUSLINE_SEGMENTS": "model,eff,ctx,git,5h,7d",
                "CODEX_STATUSLINE_NOW_EPOCH": "1773350100",
            },
        )

        self.assertNotIn("notify ", output)

    def test_codex_bars_overview_includes_notify_segment(self):
        notify_cache = Path(self.temp_dir.name) / "notify-cache.json"
        notify_cache.write_text(json.dumps({
            "summary": "Task finished",
            "updated_at": 1773350000,
        }))

        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_NOTIFY_SEGMENT": "true",
                "CODEX_STATUSLINE_NOTIFY_CACHE_FILE": str(notify_cache),
                "CODEX_STATUSLINE_NOW_EPOCH": "1773350100",
            },
        )
        lines = output.splitlines()

        self.assertEqual(4, len(lines))
        self.assertIn("notify Task finished", lines[1])

    def test_codex_segments_filter_can_hide_hook_segment(self):
        hook_cache = Path(self.temp_dir.name) / "hook-cache.json"
        hook_cache.write_text(json.dumps({
            "hook_event_name": "PostToolUse",
            "summary": "bash ok",
            "updated_at": 1773350000,
        }))

        output = self._run_codex(
            budget=180,
            extra_env={
                "CODEX_STATUSLINE_SHOW_HOOK_SEGMENT": "true",
                "CODEX_STATUSLINE_HOOK_CACHE_FILE": str(hook_cache),
                "CODEX_STATUSLINE_SEGMENTS": "model,eff,ctx,git,5h,7d",
                "CODEX_STATUSLINE_NOW_EPOCH": "1773350100",
            },
        )

        self.assertNotIn("hook ", output)

    def test_codex_five_hour_segment(self):
        output = self._run_codex(budget=150)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", output)

    def test_codex_seven_day_segment(self):
        output = self._run_codex(budget=150)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left", output)

    def test_codex_two_week_segment_shows_absolute_reset_time(self):
        output = self._run_codex(budget=150)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left {CODEX_2W_TIME}", output)

    def test_codex_custom_two_week_time_format_applies_in_compact_layout(self):
        output = self._run_codex(
            budget=150,
            extra_env={"CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT": "%y-%m-%d %H:%M"},
        )
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left {CUSTOM_CODEX_2W_TIME}", output)

    def test_codex_invalid_two_week_time_format_falls_back_to_default(self):
        output = self._run_codex(
            budget=150,
            extra_env={"CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT": "%q-%m"},
        )
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left {CODEX_2W_TIME}", output)

    def test_codex_rate_limits_null(self):
        """When rate_limits.primary is null, show placeholder."""
        session_file = self.session_dir / "rollout-test.jsonl"
        session_file.write_text(json.dumps(CODEX_TOKEN_COUNT_NULL_LIMITS) + "\n")
        output = self._run_codex(budget=150, write_session=False)
        self.assertIn("5h -", output)
        self.assertIn("weekly -", output)

    def test_codex_falls_back_to_recent_non_null_rate_limits_from_older_session(self):
        older_dir = self.codex_home / "sessions" / "2026" / "03" / "10"
        older_dir.mkdir(parents=True)
        (older_dir / "rollout-older.jsonl").write_text(json.dumps(CODEX_TOKEN_COUNT_EVENT) + "\n")

        newer_dir = self.codex_home / "sessions" / "2026" / "03" / "12"
        newer_dir.mkdir(parents=True)
        (newer_dir / "rollout-newer.jsonl").write_text(json.dumps(CODEX_TOKEN_COUNT_NULL_LIMITS) + "\n")

        output = self._run_codex(budget=150, write_session=False)
        self.assertIn("ctx 51k/258k 19%", output)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", output)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left", output)

    def test_codex_keeps_last_known_rate_limits_stable_when_new_sessions_are_null(self):
        self._write_session([CODEX_TOKEN_COUNT_EVENT])
        seeded_output = self._run_codex(budget=150, write_session=False)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", seeded_output)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left", seeded_output)

        for session_file in (self.codex_home / "sessions").glob("**/*.jsonl"):
            session_file.unlink()

        newer_dir = self.codex_home / "sessions" / "2026" / "03" / "12"
        newer_dir.mkdir(parents=True)
        (newer_dir / "rollout-newer.jsonl").write_text(json.dumps(CODEX_TOKEN_COUNT_NULL_LIMITS) + "\n")

        output = self._run_codex(budget=150, write_session=False)
        self.assertIn("ctx 51k/258k 19%", output)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", output)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left", output)

    def test_codex_wide_budget_all_segments(self):
        output = self._run_codex(budget=150)
        self.assertIn("gpt-5.4 | eff high | ctx 89k/258k 34% | git feat/codex-test", output)
        self.assertNotIn("codex-repo |", output)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", output)
        self.assertIn(f"weekly {CODEX_WEEKLY_LEFT}% left", output)
        self.assertLessEqual(len(output), 150)

    def test_codex_narrow_budget_truncation(self):
        output = self._run_codex(budget=78)
        self.assertIn("gpt-5.4", output)
        self.assertIn("eff high", output)
        self.assertIn("ctx 89k/258k 34%", output)
        self.assertIn("git ", output)
        self.assertIn(f"5h {CODEX_5H_LEFT}% left", output)
        # weekly should be dropped at narrow width
        self.assertNotIn("weekly ", output)
        self.assertLessEqual(len(output), 78)

    def test_codex_remaining_usage_colors_follow_left_percent(self):
        raw_output = self._run_codex(budget=150, raw=True)

        self.assertIn(f"5h\x1b[0m \x1b[38;2;0;160;0m{CODEX_5H_LEFT}% left", raw_output)
        self.assertIn(f"weekly\x1b[0m \x1b[38;2;0;160;0m{CODEX_WEEKLY_LEFT}% left", raw_output)

    def test_codex_theme_changes_ansi_only(self):
        default_raw = self._run_codex(budget=150, raw=True)
        dracula_raw = self._run_codex(
            budget=150,
            raw=True,
            extra_env={"CODEX_STATUSLINE_THEME": "dracula"},
        )
        # Different ANSI codes
        self.assertIn("[38;2;77;166;255m", default_raw)
        self.assertIn("[38;2;189;147;249m", dracula_raw)
        # Same plain text
        self.assertEqual(strip_ansi(default_raw), strip_ansi(dracula_raw))

    def test_codex_bars_layout(self):
        output = self._run_codex(
            budget=120,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertEqual("codex-repo@feat/codex-test", lines[0])
        self.assertEqual("gpt-5.4 | eff high | ctx 89k/258k 34%", lines[1])
        self.assertNotIn("5h ", lines[1])
        self.assertNotIn("weekly ", lines[1])
        self.assertRegex(lines[2], rf"^5h {CODEX_5H_LEFT}% left \[[=\-]+\] \d{{2}}:\d{{2}} reset$")
        self.assertRegex(lines[3], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CODEX_2W_TIME)}$")

    def test_codex_bars_layout_hides_git_line_with_env(self):
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_GIT_LINE": "false",
            },
        )
        lines = output.splitlines()
        self.assertEqual(3, len(lines))
        self.assertEqual("gpt-5.4 | eff high | ctx 89k/258k 34%", lines[0])
        self.assertRegex(lines[1], rf"^5h {CODEX_5H_LEFT}% left \[[=\-]+\] \d{{2}}:\d{{2}} reset$")
        self.assertRegex(lines[2], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CODEX_2W_TIME)}$")
        self.assertEqual(
            "",
            self._run_codex(
                budget=120,
                extra_env={
                    "CODEX_STATUSLINE_LAYOUT": "bars",
                    "CODEX_STATUSLINE_SHOW_GIT_LINE": "false",
                },
                args=["--line", "1"],
            ).strip(),
        )

    def test_codex_bars_layout_hides_overview_line_with_env(self):
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_OVERVIEW_LINE": "off",
            },
        )
        lines = output.splitlines()
        self.assertEqual(3, len(lines))
        self.assertEqual("codex-repo@feat/codex-test", lines[0])
        self.assertRegex(lines[1], rf"^5h {CODEX_5H_LEFT}% left \[[=\-]+\] \d{{2}}:\d{{2}} reset$")
        self.assertRegex(lines[2], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CODEX_2W_TIME)}$")
        self.assertEqual(
            "",
            self._run_codex(
                budget=120,
                extra_env={
                    "CODEX_STATUSLINE_LAYOUT": "bars",
                    "CODEX_STATUSLINE_SHOW_OVERVIEW_LINE": "off",
                },
                args=["--line", "2"],
            ).strip(),
        )

    def test_codex_bars_layout_hides_both_top_lines_with_config(self):
        self._write_codex_config(
            'layout = "bars"\nshow_git_line = false\nshow_overview_line = false\n'
        )
        output = self._run_codex(budget=120, layout=None)
        lines = output.splitlines()
        self.assertEqual(2, len(lines))
        self.assertRegex(lines[0], rf"^5h {CODEX_5H_LEFT}% left \[[=\-]+\] \d{{2}}:\d{{2}} reset$")
        self.assertRegex(lines[1], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CODEX_2W_TIME)}$")
        self.assertEqual("", self._run_codex(budget=120, layout=None, args=["--line", "1"]).strip())
        self.assertEqual("", self._run_codex(budget=120, layout=None, args=["--line", "2"]).strip())

    def test_codex_bars_layout_visibility_uses_config_when_env_missing(self):
        self._write_codex_config(
            'layout = "bars"\nshow_git_line = false\nshow_overview_line = true\n'
        )
        output = self._run_codex(budget=120, layout=None)
        lines = output.splitlines()
        self.assertEqual(3, len(lines))
        self.assertEqual("gpt-5.4 | eff high | ctx 89k/258k 34%", lines[0])
        self.assertEqual("", self._run_codex(budget=120, layout=None, args=["--line", "1"]).strip())
        self.assertEqual("gpt-5.4 | eff high | ctx 89k/258k 34%", self._run_codex(budget=120, layout=None, args=["--line", "2"]).strip())

    def test_codex_bars_layout_visibility_env_overrides_config(self):
        self._write_codex_config(
            'layout = "bars"\nshow_git_line = false\nshow_overview_line = false\n'
        )
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_GIT_LINE": "true",
                "CODEX_STATUSLINE_SHOW_OVERVIEW_LINE": "true",
            },
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertEqual("codex-repo@feat/codex-test", lines[0])
        self.assertEqual("gpt-5.4 | eff high | ctx 89k/258k 34%", lines[1])

    def test_codex_bars_layout_invalid_visibility_value_falls_back_to_visible(self):
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_GIT_LINE": "maybe",
            },
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertEqual("codex-repo@feat/codex-test", lines[0])

    def test_codex_bars_layout_uses_custom_two_week_time_format(self):
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT": "%y-%m-%d %H:%M",
            },
        )
        lines = output.splitlines()
        self.assertRegex(lines[3], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CUSTOM_CODEX_2W_TIME)}$")

    def test_codex_bars_layout_narrow_width_keeps_two_week_absolute_time(self):
        output = self._run_codex(
            budget=44,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT": "%y-%m-%d %H:%M",
            },
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertRegex(lines[0], r"^codex-repo@.+$")
        self.assertRegex(lines[3], rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\]( {re.escape(CODEX_2W_SHORT_DATE)})?$")

    def test_codex_no_session_graceful(self):
        """No session file at all — should not crash."""
        output = self._run_codex(budget=150, write_session=False)
        self.assertIn("gpt-5.4", output)
        self.assertIn("ctx 0/0 0%", output)
        self.assertIn("5h -", output)
        self.assertIn("weekly -", output)

    def test_codex_git_dirty_diff(self):
        (self.repo / "tracked.txt").write_text("base\nchange\n")
        output = self._run_codex(budget=150)
        self.assertIn("git feat/codex-test", output)
        self.assertRegex(output, r"\(\+\d+ -\d+\)")

    def test_codex_empty_session_dir(self):
        """Session dir exists but has no .jsonl files."""
        # Remove session file if present
        for f in self.session_dir.glob("*.jsonl"):
            f.unlink()
        output = self._run_codex(budget=150, write_session=False)
        self.assertIn("gpt-5.4", output)
        self.assertIn("5h -", output)
        self.assertIn("weekly -", output)

    def test_codex_no_extra_segment(self):
        """Codex should never show extra usage segment."""
        output = self._run_codex(budget=200)
        self.assertNotIn("extra ", output)

    def test_codex_bars_layout_without_usage(self):
        output = self._run_codex(
            budget=120,
            write_session=False,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertEqual("codex-repo@feat/codex-test", lines[0])
        self.assertEqual("5h unavailable", lines[2])
        self.assertEqual("weekly unavailable", lines[3])

    def test_codex_bars_layout_null_rate_limits_uses_unavailable_copy(self):
        session_file = self.session_dir / "rollout-test.jsonl"
        session_file.write_text(json.dumps(CODEX_TOKEN_COUNT_NULL_LIMITS) + "\n")

        output = self._run_codex(
            budget=120,
            write_session=False,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertEqual("5h unavailable", lines[2])
        self.assertEqual("weekly unavailable", lines[3])

    def test_codex_bars_layout_dots_style(self):
        output = self._run_codex(
            budget=120,
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_BAR_STYLE": "dots",
            },
        )
        lines = output.splitlines()
        self.assertEqual(4, len(lines))
        self.assertIn("\u25cf", lines[2])  # ●
        self.assertIn("\u25cb", lines[2])  # ○

    def test_codex_bars_git_line_uses_accessible_secondary_palette(self):
        raw_output = self._run_codex(
            budget=120,
            raw=True,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
        )
        git_line = raw_output.splitlines()[0]

        self.assertIn(DEFAULT_SECONDARY_ANSI, git_line)
        self.assertNotIn("[38;2;77;175;176m", git_line)
        self.assertNotIn("[38;2;196;208;212m", git_line)

    def test_codex_bars_layout_line_selection_matches_new_order(self):
        git_line = self._run_codex(
            budget=120,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
            args=["--line", "1"],
        ).strip()
        weekly_line = self._run_codex(
            budget=120,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
            args=["--line", "4"],
        ).strip()

        self.assertEqual("codex-repo@feat/codex-test", git_line)
        self.assertRegex(weekly_line, rf"^weekly {CODEX_WEEKLY_LEFT}% left \[[=\-]+\] {re.escape(CODEX_2W_TIME)}$")

    def test_codex_tmux_launcher_hides_git_line_with_env(self):
        tmux_lines = self._run_codex_tmux_launcher(
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_GIT_LINE": "false",
            },
        )
        joined = "\n".join(tmux_lines)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus\t3", joined)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus-format[0]\t  #(", joined)
        self.assertIn("--line 2)", joined)
        self.assertIn("status-format[1]", joined)
        self.assertIn("--line 3)", joined)
        self.assertIn("status-format[2]", joined)
        self.assertIn("--line 4)", joined)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus-format[3]\t", joined)

    def test_codex_tmux_launcher_hides_both_top_lines_with_config(self):
        tmux_lines = self._run_codex_tmux_launcher(
            extra_env={"CODEX_STATUSLINE_LAYOUT": "bars"},
            config_statusline='layout = "bars"\nshow_git_line = false\nshow_overview_line = false\n',
        )
        joined = "\n".join(tmux_lines)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus\t2", joined)
        self.assertIn("status-format[0]", joined)
        self.assertIn("--line 3)", joined)
        self.assertIn("status-format[1]", joined)
        self.assertIn("--line 4)", joined)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus-format[2]\t", joined)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus-format[3]\t", joined)

    def test_codex_tmux_launcher_visibility_env_overrides_config(self):
        tmux_lines = self._run_codex_tmux_launcher(
            extra_env={
                "CODEX_STATUSLINE_LAYOUT": "bars",
                "CODEX_STATUSLINE_SHOW_GIT_LINE": "true",
                "CODEX_STATUSLINE_SHOW_OVERVIEW_LINE": "true",
            },
            config_statusline='layout = "bars"\nshow_git_line = false\nshow_overview_line = false\n',
        )
        joined = "\n".join(tmux_lines)
        self.assertIn("set-option\t-t\tcodex-codex-repo\t-q\tstatus\t4", joined)
        self.assertIn("--line 1)", joined)
        self.assertIn("--line 2)", joined)
        self.assertIn("--line 3)", joined)
        self.assertIn("--line 4)", joined)

    def test_codex_unknown_layout_falls_back_to_bars(self):
        bars_output = self._run_codex(budget=100, layout="bars")
        unknown_output = self._run_codex(
            budget=100,
            layout=None,
            extra_env={"CODEX_STATUSLINE_LAYOUT": "mystery"},
        )
        self.assertEqual(bars_output, unknown_output)

    def test_codex_segments_filter_hides_model(self):
        output = self._run_codex(budget=150, extra_env={
            "CODEX_STATUSLINE_SEGMENTS": "eff,ctx,git,5h,7d",
        })
        self.assertNotIn("gpt-5.4", output)
        self.assertIn("eff", output)

    def test_codex_segments_filter_empty_shows_all(self):
        output = self._run_codex(budget=150, extra_env={
            "CODEX_STATUSLINE_SEGMENTS": "",
        })
        self.assertIn("gpt-5.4", output)
        self.assertIn("eff", output)

    def test_codex_segments_filter_hides_5h_and_7d(self):
        output = self._run_codex(budget=150, extra_env={
            "CODEX_STATUSLINE_SEGMENTS": "model,eff,ctx",
        })
        self.assertNotIn("5h", output)
        self.assertNotIn("weekly", output)

    def test_codex_all_themes_same_plain_text(self):
        default_plain = self._run_codex(budget=100)
        for theme in ["forest", "dracula", "monokai", "solarized", "ocean", "sunset", "amber", "rose"]:
            themed = self._run_codex(
                budget=100,
                extra_env={"CODEX_STATUSLINE_THEME": theme},
            )
            self.assertEqual(
                default_plain, themed,
                f"Theme '{theme}' changed plain text output",
            )


if __name__ == "__main__":
    unittest.main()
