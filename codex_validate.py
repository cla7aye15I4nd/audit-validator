#!/usr/bin/env python3
"""Run fp-check validation through the Codex CLI."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

SKILL_NAME = "fp-check"
DEFAULT_MODEL = "gpt-5"
PROJECT_ROOT = Path(__file__).resolve().parent


def default_codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()


def installed_skill_dir(codex_home: Path) -> Path:
    return codex_home.expanduser() / "skills" / SKILL_NAME


def require_installed_skill(codex_home: Path) -> Path:
    skill_dir = installed_skill_dir(codex_home)
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.is_file():
        raise FileNotFoundError(
            f"{SKILL_NAME} is not installed at {skill_dir}. Install it locally before running validation."
        )
    return skill_dir


def build_validation_prompt(source: Path, finding: Path) -> str:
    return (
        "Use the fp-check skill to verify the following smart contract security finding. "
        "Apply the full verification methodology and return a TRUE POSITIVE or FALSE POSITIVE "
        "verdict with supporting evidence.\n\n"
        f"Source directory: {source.resolve()}\n\n"
        f"Finding:\n{finding.read_text(encoding='utf-8')}"
    )


def build_codex_command(source: Path, finding: Path, model: str) -> list[str]:
    return [
        "codex",
        "exec",
        "--skip-git-repo-check",
        "--dangerously-bypass-approvals-and-sandbox",
        "--cd",
        str(PROJECT_ROOT),
        "--add-dir",
        str(source.resolve()),
        "--model",
        model,
        build_validation_prompt(source, finding),
    ]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a finding with Codex using the installed fp-check skill.")
    parser.add_argument("source", type=Path, help="Path to the smart contract source directory.")
    parser.add_argument("finding", type=Path, help="Path to the finding file.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Codex model to use. Default: {DEFAULT_MODEL}.")
    parser.add_argument(
        "--codex-home",
        type=Path,
        default=default_codex_home(),
        help="Codex home directory. Defaults to $CODEX_HOME or ~/.codex.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not args.source.is_dir():
        print(f"[ERROR] Source directory not found: {args.source}", file=sys.stderr)
        return 1
    if not args.finding.is_file():
        print(f"[ERROR] Finding file not found: {args.finding}", file=sys.stderr)
        return 1

    try:
        skill_dir = require_installed_skill(args.codex_home)
    except FileNotFoundError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    env = os.environ.copy()
    env["CODEX_HOME"] = str(args.codex_home)

    print(f"Using skill: {skill_dir}")
    completed = subprocess.run(
        build_codex_command(args.source, args.finding, args.model),
        env=env,
        cwd=PROJECT_ROOT,
    )
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
