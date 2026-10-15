#!/usr/bin/env python3
"""Select an agent login without replacing another account's credentials."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ACCOUNTS = {
    ("codex", "office"): ("office@marianomiguel.com", ".codex"),
    ("codex", "personal"): ("marianojmig@gmail.com", ".local/share/agent-accounts/codex-personal"),
    ("claude", "office"): ("office@marianomiguel.com", ".claude"),
    ("claude", "monarch"): ("mariano.miguel@monarchmd.com", ".local/share/agent-accounts/claude-monarch"),
}


def profile(tool, account, home=None):
    email, relative = ACCOUNTS[(tool, account)]
    return email, (home or Path.home()) / relative


def environment(tool, directory, source=None):
    env = dict(os.environ if source is None else source)
    variable = "CODEX_HOME" if tool == "codex" else "CLAUDE_CONFIG_DIR"
    if directory == Path.home() / (".codex" if tool == "codex" else ".claude"):
        # Claude's default ~/.claude.json sits outside ~/.claude. Explicitly
        # setting CLAUDE_CONFIG_DIR relocates that file even for ~/.claude.
        env.pop(variable, None)
    else:
        env[variable] = str(directory)
    # Explicit subscription selection must not silently spend API credits or
    # use a token inherited from the parent agent process.
    for key in (
        "OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN",
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
        "ANTHROPIC_BASE_URL", "ANTHROPIC_CUSTOM_HEADERS",
    ):
        env.pop(key, None)
    return env


def prepare(home=None):
    for tool, account in ACCOUNTS:
        if account == "office":
            continue  # Existing desktop and CLI logins stay where they are.
        _, directory = profile(tool, account, home)
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        config = directory / ("config.toml" if tool == "codex" else "settings.json")
        if config.exists():
            continue
        content = (
            'cli_auth_credentials_store = "file"\n\n'
            '[mcp_servers.superhuman-mail]\nurl = "https://mcp.mail.superhuman.com/mcp"\n\n'
            '[mcp_servers.granola]\nurl = "https://mcp.granola.ai/mcp"\n'
            if tool == "codex" else '{}\n'
        )
        with config.open("x") as stream:
            stream.write(content)
        config.chmod(0o600)


def identity(tool, directory):
    """Return only the account email; never emit credential contents."""
    if tool == "codex":
        path = directory / "auth.json"
        if not path.exists():
            return None
        try:
            auth = json.loads(path.read_text())
            token = auth.get("tokens", {}).get("id_token", "")
            payload = token.split(".")[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
            # This is an identity label, not validation of token freshness.
            return claims.get("email")
        except (ValueError, KeyError, IndexError, TypeError):
            return None
    if not directory.exists():
        return None
    result = subprocess.run(
        ["claude", "auth", "status"], env=environment(tool, directory),
        capture_output=True, text=True, timeout=20,
    )
    try:
        auth = json.loads(result.stdout)
        return auth.get("email") if auth.get("loggedIn") else None
    except ValueError:
        return None


def check_identity(tool, account, directory):
    expected, _ = profile(tool, account)
    actual = identity(tool, directory)
    if actual != expected:
        label = actual or "not signed in / identity unavailable"
        raise ValueError(f"{tool}/{account}: {label}; expected {expected}. "
                         f"Run agent-account login {tool} {account}.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list", help="Show expected and cached account identities")
    sub.add_parser("prepare", help="Create private directories for the additional accounts")
    for action in ("login", "codex", "claude"):
        p = sub.add_parser(action)
        if action == "login":
            p.add_argument("tool", choices=["codex", "claude"])
            p.add_argument("account")
        else:
            p.add_argument("account", choices=[a for t, a in ACCOUNTS if t == action])
            p.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.action == "prepare":
        prepare()
        print("Private profiles prepared. Existing office credentials are unchanged.")
        return
    if args.action == "list":
        for tool, account in ACCOUNTS:
            expected, directory = profile(tool, account)
            actual = identity(tool, directory)
            label = "cached identity matches; expiry not checked" if actual == expected else (actual or "login required")
            print(f"{tool:6} {account:8} {expected:33} {label}")
        return
    tool = args.tool if args.action == "login" else args.action
    if (tool, args.account) not in ACCOUNTS:
        parser.error(f"No {tool} profile named {args.account}")
    expected, directory = profile(tool, args.account)
    prepare()
    env = environment(tool, directory)
    if args.action == "login":
        print(f"Sign in as {expected}. This profile: {directory}", flush=True)
        command = [tool, "login", "--device-auth"] if tool == "codex" else [tool, "auth", "login", "--claudeai", "--email", expected]
        result = subprocess.run(command, env=env)
        if result.returncode:
            return result.returncode
        check_identity(tool, args.account, directory)
        print(f"Verified {tool}/{args.account}: {expected}")
        return
    # Authentication commands remain usable when a token has expired or a
    # mistaken login must be fixed. Agent runs require the intended identity.
    arguments = args.arguments
    if arguments[:1] not in (["login"], ["logout"], ["auth"], ["mcp"], ["--help"], ["--version"]):
        check_identity(tool, args.account, directory)
    executable = shutil.which(tool)
    if not executable:
        raise ValueError(f"{tool} is not installed or not on PATH")
    os.execve(executable, [tool, *arguments], env)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
