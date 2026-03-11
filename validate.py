import asyncio
import argparse
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

# Unset CLAUDECODE so spawned claude-code subprocesses don't refuse to run
os.environ.pop("CLAUDECODE", None)

from pydantic import BaseModel
from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
)


class BugVerdict(BaseModel):
    is_valid: bool  # true = real vulnerability, false = false positive
    explanation: str  # brief explanation with key evidence


def finding_to_prompt(finding: dict) -> str:
    """Convert a finding JSON object into a structured prompt string."""
    loc = finding.get("location", {})
    lines = [
        f"Title: {finding.get('title', 'N/A')}",
        f"Severity: {finding.get('severity', 'N/A')}",
        f"File: {loc.get('local_file_path', 'N/A')} (lines {loc.get('start_line', '?')}-{loc.get('end_line', '?')})",
        "",
        "Description:",
        finding.get("description", "").strip(),
    ]
    if finding.get("related_function_code"):
        lines += [
            "",
            "Related Function Code:",
            "```",
            finding["related_function_code"].strip(),
            "```",
        ]
    if finding.get("recommendation"):
        lines += ["", f"Recommendation: {finding['recommendation']}"]
    return "\n".join(lines)


async def verify_finding(
    finding: dict,
    project_dir: str,
    plugin_path: str,
    max_retries: int = 3,
) -> BugVerdict:
    base_prompt = (
        "Verify the following suspected security bug. "
        "Use the fp-check skill to perform systematic false positive verification. "
        "Complete all phases and gate reviews before producing the final verdict.\n\n"
        + finding_to_prompt(finding)
    )

    options = ClaudeAgentOptions(
        plugins=[{"type": "local", "path": str(Path(plugin_path).resolve())}],
        cwd=str(Path(project_dir).resolve()),
        allowed_tools=[
            "Skill",
            "Read",
            "Grep",
            "Glob",
            "Bash",
            "Write",
            "Edit",
            "Task",
            "TodoRead",
            "TodoWrite",
        ],
        permission_mode="acceptEdits",
        system_prompt={
            "type": "preset",
            "preset": "claude_code",
            "append": (
                "You have the fp-check plugin loaded. "
                "Use it for systematic verification. "
                "Complete all phases and gate reviews. "
                "is_valid = true means real vulnerability, false means false positive. "
                "IMPORTANT: Base your verdict solely on code analysis. "
                "Do NOT use file names, directory names, or any naming conventions "
                "(such as 'tp_' or 'fp_' prefixes) as evidence — these are internal "
                "dataset labels and must be ignored entirely."
            ),
        },
        setting_sources=["project"],
        output_format={
            "type": "json_schema",
            "schema": BugVerdict.model_json_schema(),
        },
    )

    for attempt in range(1, max_retries + 1):
        if attempt > 1:
            print(f"  [Retry {attempt}/{max_retries}] No structured output on previous attempt, retrying...")
        prompt = base_prompt
        if attempt > 1:
            prompt += (
                "\n\nIMPORTANT: You MUST produce a structured JSON verdict with "
                "'is_valid' (bool) and 'explanation' (str) fields to complete this task."
            )

        got_output = False
        result = None
        gen = query(prompt=prompt, options=options)
        try:
            async for message in gen:
                if isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            print(f"  [Assistant] {block.text}")
                        elif isinstance(block, ToolUseBlock):
                            print(f"  [Tool] {block.name}: {block.input}")
                elif isinstance(message, ResultMessage) and message.structured_output:
                    got_output = True
                    result = BugVerdict.model_validate(message.structured_output)
                    break
        finally:
            await gen.aclose()

        if got_output and result is not None:
            return result

    raise RuntimeError(f"No structured output returned after {max_retries} attempts")


def _process_finding_worker(args: tuple) -> None:
    finding_path_str, plugin_path = args
    asyncio.run(process_finding_file(Path(finding_path_str), plugin_path))


async def process_finding_file(finding_path: Path, plugin_path: str) -> None:
    finding = json.loads(finding_path.read_text())
    project_dir = str(finding_path.parent)
    finding_id = finding.get("id", finding_path.stem)

    print(f"\n{'='*60}")
    print(f"Verifying: {finding.get('title', finding_id)}")
    print(f"File: {finding_path}")
    print(f"Project dir: {project_dir}")

    try:
        verdict = await verify_finding(finding, project_dir, plugin_path)
        icon = "TRUE POSITIVE" if verdict.is_valid else "FALSE POSITIVE"
        print(f"\n[{icon}]")
        print(f"Explanation: {verdict.explanation}")

        out_path = finding_path.with_suffix(".result.json")
        out_path.write_text(
            json.dumps({"finding_id": finding_id, **verdict.model_dump()}, indent=2)
        )
        print(f"Saved to: {out_path}")
    except RuntimeError as e:
        print(f"  [ERROR] {e}")


async def main_async():
    parser = argparse.ArgumentParser(
        description="Validate security findings using fp-check."
    )
    parser.add_argument(
        "finding",
        nargs="?",
        help="Path to a single finding JSON file. If omitted, all findings in ./dataset are processed.",
    )
    parser.add_argument(
        "--plugin-path",
        type=str,
        default="./skills/plugins/fp-check",
        help="Path to the fp-check plugin directory",
    )
    parser.add_argument(
        "--dataset-dir",
        type=str,
        default="./dataset",
        help="Root directory to scan for findings in batch mode (default: ./dataset)",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Number of parallel worker processes in batch mode (default: 4)",
    )
    args = parser.parse_args()

    if args.finding:
        await process_finding_file(Path(args.finding), args.plugin_path)
    else:
        dataset_dir = Path(args.dataset_dir)
        finding_paths = sorted(
            p for p in dataset_dir.rglob("*.json")
            if "finding" in p.name
            and not p.name.endswith(".result.json")
            and "src" not in p.parts
            and not p.with_suffix(".result.json").exists()
        )

        if not finding_paths:
            print(f"No finding JSON files found in {dataset_dir}")
            sys.exit(1)

        print(f"Batch mode: found {len(finding_paths)} finding(s) to process (workers={args.workers})")
        worker_args = [(str(p), args.plugin_path) for p in finding_paths]
        with ProcessPoolExecutor(max_workers=args.workers) as executor:
            list(executor.map(_process_finding_worker, worker_args))


if __name__ == "__main__":
    asyncio.run(main_async())
