import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHELL_SCRIPT = ROOT / "statusline.sh"
PS_SCRIPT = ROOT / "statusline.ps1"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

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
    "five_hour": {"utilization": 83, "resets_at": "2026-03-11T02:00:00Z"},
    "seven_day": {"utilization": 63, "resets_at": "2026-03-06T08:00:00Z"},
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

    def _run_shell(self, budget=None, usage=True, cwd=None):
        env = os.environ.copy()
        env["HOME"] = str(self.cache_home)
        env["TZ"] = "UTC"
        env["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
        if budget is not None:
            env["CLAUDE_CODE_STATUSLINE_MAX_WIDTH"] = str(budget)
        else:
            env.pop("CLAUDE_CODE_STATUSLINE_MAX_WIDTH", None)

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
        return strip_ansi(result.stdout)

    def _run_pwsh(self, budget=None):
        runtime = shutil.which("pwsh") or shutil.which("powershell")
        if runtime is None:
            self.skipTest("PowerShell runtime unavailable")

        self._write_usage(SAMPLE_USAGE)
        env = os.environ.copy()
        env["HOME"] = str(self.cache_home)
        env["USERPROFILE"] = str(self.cache_home)
        env["TZ"] = "UTC"
        env["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
        if budget is not None:
            env["CLAUDE_CODE_STATUSLINE_MAX_WIDTH"] = str(budget)
        else:
            env.pop("CLAUDE_CODE_STATUSLINE_MAX_WIDTH", None)

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
        output = self._run_shell(budget=130)
        self.assertIn("Opus 4.6", output)
        self.assertIn("ctx 15k/200k 7%", output)
        self.assertIn("eff low", output)
        self.assertIn("5h 83% 2:00", output)
        self.assertIn("7d 63% Mar 6 8:00", output)
        self.assertIn("extra $12.34/$20.00", output)
        self.assertLessEqual(len(output), 130)

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
        self.assertNotIn("extra ", pwsh_output)
        self.assertEqual(shell_output.split(" | ")[:4], pwsh_output.split(" | ")[:4])


if __name__ == "__main__":
    unittest.main()
