import asyncio
import argparse
import json
import sys
from pathlib import Path

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
    model: str | None = None,
    verbose: bool = False,
) -> BugVerdict:
    prompt = (
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
                "is_valid = true means real vulnerability, false means false positive."
            ),
        },
        setting_sources=["project"],
        output_format={
            "type": "json_schema",
            "schema": BugVerdict.model_json_schema(),
        },
    )

    if model:
        options.model = model

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage) and verbose:
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)
                elif isinstance(block, ToolUseBlock):
                    print(f"  [Tool] {block.name}")
        elif isinstance(message, ResultMessage) and message.structured_output:
            return BugVerdict.model_validate(message.structured_output)

    raise RuntimeError("No structured output returned")


async def main_async():
    parser = argparse.ArgumentParser(
        description="Validate security findings using fp-check."
    )
    parser.add_argument(
        "finding",
        nargs="?",
        help="Path to a single finding JSON file (e.g. dataset/ABConnect/tp_finding_01.json)",
    )
    parser.add_argument(
        "--plugin-path",
        type=str,
        default="./skills/plugins/fp-check",
        help="Path to the fp-check plugin directory",
    )
    parser.add_argument("--model", type=str, default=None)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--output", type=str, default=None)
    args = parser.parse_args()

    if not args.finding:
        parser.print_help()
        sys.exit(1)

    finding_path = Path(args.finding)
    finding = json.loads(finding_path.read_text())
    project_dir = str(finding_path.parent)

    finding_id = finding.get("id", finding_path.stem)
    print(f"Verifying: {finding.get('title', finding_id)}")
    print(f"Project dir: {project_dir}")

    verdict = await verify_finding(
        finding,
        project_dir,
        args.plugin_path,
        args.model,
        args.verbose,
    )
    icon = "TRUE POSITIVE" if verdict.is_valid else "FALSE POSITIVE"
    print(f"\n[{icon}]")
    print(f"Explanation: {verdict.explanation}")

    out_path = args.output or str(finding_path.with_suffix(".result.json"))
    Path(out_path).write_text(
        json.dumps({"finding_id": finding_id, **verdict.model_dump()}, indent=2)
    )
    print(f"Saved to: {out_path}")


if __name__ == "__main__":
    asyncio.run(main_async())
