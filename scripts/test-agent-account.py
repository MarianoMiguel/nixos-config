#!/usr/bin/env python3
"""Exercise account isolation and failure behavior without real credentials."""
import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("agent_account", Path(__file__).with_name("agent-account.py"))
account = importlib.util.module_from_spec(spec)
spec.loader.exec_module(account)


class AccountIsolation(unittest.TestCase):
    def test_prepare_preserves_office_and_existing_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            office = home / ".codex"
            office.mkdir()
            credential = office / "auth.json"
            credential.write_text("existing private login")
            account.prepare(home)
            _, personal = account.profile("codex", "personal", home)
            self.assertEqual(personal.stat().st_mode & 0o777, 0o700)
            self.assertEqual((personal / "config.toml").stat().st_mode & 0o777, 0o600)
            self.assertFalse((personal / "auth.json").exists())
            (personal / "config.toml").write_text("user customization")
            account.prepare(home)
            self.assertEqual((personal / "config.toml").read_text(), "user customization")
            self.assertEqual(credential.read_text(), "existing private login")

    def test_profile_overrides_parent_without_inherited_api_credentials(self):
        parent = {"CODEX_HOME": "/wrong", "OPENAI_API_KEY": "secret", "ANTHROPIC_API_KEY": "secret", "PATH": "/bin"}
        result = account.environment("codex", Path("/right"), parent)
        self.assertEqual(result["CODEX_HOME"], "/right")
        self.assertEqual(result["PATH"], "/bin")
        self.assertNotIn("OPENAI_API_KEY", result)
        self.assertNotIn("ANTHROPIC_API_KEY", result)
        self.assertEqual(parent["CODEX_HOME"], "/wrong")

    def test_wrong_account_and_missing_login_block_execution(self):
        for actual in ("wrong@example.com", None):
            with patch.object(account, "identity", return_value=actual):
                with self.assertRaises(ValueError):
                    account.check_identity("codex", "personal", Path("/unused"))
        with patch.object(account, "identity", return_value="marianojmig@gmail.com"):
            account.check_identity("codex", "personal", Path("/unused"))

    def test_office_claude_uses_the_original_default_signin_location(self):
        result = account.environment("claude", Path.home() / ".claude", {"CLAUDE_CONFIG_DIR": "/other-account"})
        self.assertNotIn("CLAUDE_CONFIG_DIR", result)

    def test_cached_identity_reports_only_email_and_handles_invalid_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertIsNone(account.identity("codex", root))
            payload = base64.urlsafe_b64encode(json.dumps({"email": "example@example.com"}).encode()).decode().rstrip("=")
            (root / "auth.json").write_text(json.dumps({"tokens": {"id_token": f"header.{payload}.signature"}}))
            self.assertEqual(account.identity("codex", root), "example@example.com")
            (root / "auth.json").write_text("{}")
            self.assertIsNone(account.identity("codex", root))


if __name__ == "__main__":
    unittest.main()
