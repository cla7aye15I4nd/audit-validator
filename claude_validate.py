#!/usr/bin/env python3
import asyncio
import shutil
import sys
import uuid
from pathlib import Path

from claude_code_sdk import AssistantMessage, ClaudeCodeOptions, ResultMessage, TextBlock, query

PROJECT_ROOT = Path(__file__).parent


async def main(source: Path, finding: Path) -> int:
    workdir = Path("/tmp") / str(uuid.uuid4())
    workdir.mkdir()
    shutil.copytree(source, workdir / source.name)
    shutil.copy2(finding, workdir / finding.name)

    options = ClaudeCodeOptions(
        cwd=str(PROJECT_ROOT),
        add_dirs=[str(workdir)],
        allowed_tools=[
            "Skill", "Read", "Grep", "Glob", "Bash",
            "Write", "Edit", "Task", "TaskCreate", "TaskUpdate",
            "TaskList", "TaskGet", "AskUserQuestion",
        ],
        permission_mode="bypassPermissions",
        max_turns=50,
    )
    prompt = (
        "Use the fp-check skill to verify the following smart contract security finding. "
        "Apply the full verification methodology and return a TRUE POSITIVE or FALSE POSITIVE "
        f"verdict with supporting evidence.\n\nSource directory: {workdir / source.name}\n\n"
        f"Finding:\n{(workdir / finding.name).read_text()}"
    )
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text, end="", flush=True)
        elif isinstance(message, ResultMessage):
            cost = f"${message.total_cost_usd:.4f}" if message.total_cost_usd is not None else "n/a"
            print(f"\nTurns: {message.num_turns}  |  Cost: {cost}")
            return 1 if message.is_error else 0
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <source_dir> <finding_file>", file=sys.stderr)
        sys.exit(1)
    source, finding = Path(sys.argv[1]), Path(sys.argv[2])
    if not source.is_dir():
        print(f"error: not a directory: {source}", file=sys.stderr)
        sys.exit(1)
    if not finding.is_file():
        print(f"error: file not found: {finding}", file=sys.stderr)
        sys.exit(1)
    sys.exit(asyncio.run(main(source, finding)))
