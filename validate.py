#!/usr/bin/env python3
"""
audit-validator: False positive checker for security findings.

Uses the Claude Code Agent SDK with the fp-check skill to systematically
verify whether security findings are true positives or false positives.

Usage:
    python validate.py --finding path/to/finding.md --source path/to/source/
    python validate.py -f finding.md -s ./project -o verdict.md
"""

import argparse
import re
import sys
from pathlib import Path

import anyio
from claude_agent_sdk import (
    AgentDefinition,
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    SystemMessage,
    TextBlock,
    query,
)

# ---------------------------------------------------------------------------
# Skill loading helpers
# ---------------------------------------------------------------------------

_FRONTMATTER_RE = re.compile(r"^---\s*\n.*?\n---\s*\n", re.DOTALL)


def _strip_frontmatter(text: str) -> str:
    """Remove YAML frontmatter block from a markdown file."""
    return _FRONTMATTER_RE.sub("", text, count=1).lstrip()


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def build_system_prompt(skills_dir: Path) -> str:
    """
    Load the fp-check skill and all its reference/agent files, inlining them
    so the agent has the full methodology without needing to read files itself.

    {baseDir} placeholders in the skill are replaced with inline content.
    """
    fp_check_base = skills_dir / "plugins" / "fp-check"
    skill_dir = fp_check_base / "skills" / "fp-check"
    refs_dir = skill_dir / "references"
    agents_dir = fp_check_base / "agents"

    # Reference files keyed by their {baseDir}/references/<name>.md stem
    ref_files = {
        "standard-verification": refs_dir / "standard-verification.md",
        "deep-verification": refs_dir / "deep-verification.md",
        "gate-reviews": refs_dir / "gate-reviews.md",
        "bug-class-verification": refs_dir / "bug-class-verification.md",
        "false-positive-patterns": refs_dir / "false-positive-patterns.md",
        "evidence-templates": refs_dir / "evidence-templates.md",
    }

    # Build a map of filename → inlined section header for replacement
    ref_sections: dict[str, str] = {}
    ref_appendix_parts: list[str] = []

    for stem, path in ref_files.items():
        if not path.exists():
            continue
        content = _strip_frontmatter(_read(path))
        anchor = f"[REFERENCE: {stem}]"
        ref_sections[stem] = anchor
        ref_appendix_parts.append(
            f"\n\n---\n\n<!-- {anchor} -->\n\n{content}"
        )

    # Load and process SKILL.md
    skill_md = _strip_frontmatter(_read(skill_dir / "SKILL.md"))

    # Replace {baseDir}/references/<name>.md links with inline anchors
    def replace_ref(m: re.Match) -> str:
        stem = Path(m.group(1)).stem  # e.g. "standard-verification"
        anchor = ref_sections.get(stem, m.group(0))
        return anchor

    skill_md = re.sub(
        r"\{baseDir\}/references/([\w-]+\.md)",
        replace_ref,
        skill_md,
    )

    # Agent file appendix (informational — agents are passed via AgentDefinition)
    agent_files = {
        "data-flow-analyzer": agents_dir / "data-flow-analyzer.md",
        "exploitability-verifier": agents_dir / "exploitability-verifier.md",
        "poc-builder": agents_dir / "poc-builder.md",
    }
    agent_appendix_parts: list[str] = []
    for name, path in agent_files.items():
        if path.exists():
            content = _strip_frontmatter(_read(path))
            agent_appendix_parts.append(
                f"\n\n---\n\n## Agent spec: {name}\n\n{content}"
            )

    sections = [
        "# fp-check: False Positive Verification Skill\n\n",
        skill_md,
        "\n\n---\n\n# Inline Reference Files",
        *ref_appendix_parts,
        "\n\n---\n\n# Agent Specifications",
        *agent_appendix_parts,
    ]
    return "".join(sections)


def load_agent_prompt(skills_dir: Path, agent_name: str) -> str:
    """Load an fp-check agent's markdown file (frontmatter stripped) as its prompt."""
    path = skills_dir / "plugins" / "fp-check" / "agents" / f"{agent_name}.md"
    if not path.exists():
        return f"You are the {agent_name} agent for fp-check vulnerability verification."
    return _strip_frontmatter(_read(path))


# ---------------------------------------------------------------------------
# Core validation logic
# ---------------------------------------------------------------------------

async def validate_finding(
    finding_path: Path,
    source_dir: Path,
    output_path: Path,
    skills_dir: Path,
) -> None:
    """Run the fp-check agent on a security finding."""

    finding_content = finding_path.read_text(encoding="utf-8")

    print(f"[audit-validator] Finding : {finding_path}")
    print(f"[audit-validator] Source  : {source_dir}")
    print(f"[audit-validator] Output  : {output_path}")
    print("[audit-validator] Loading fp-check skill...")

    system_prompt = build_system_prompt(skills_dir)

    # Build subagent definitions matching the fp-check plugin agents
    agents = {
        "data-flow-analyzer": AgentDefinition(
            description=(
                "Analyzes data flow from source to vulnerability sink, mapping trust "
                "boundaries, API contracts, environment protections, and cross-references. "
                "Spawned by fp-check during Phase 1 verification."
            ),
            prompt=load_agent_prompt(skills_dir, "data-flow-analyzer"),
            tools=["Read", "Grep", "Glob"],
        ),
        "exploitability-verifier": AgentDefinition(
            description=(
                "Proves attacker control, creates mathematical bounds proofs, and assesses "
                "race condition feasibility. Spawned by fp-check during Phase 2 verification."
            ),
            prompt=load_agent_prompt(skills_dir, "exploitability-verifier"),
            tools=["Read", "Grep", "Glob"],
        ),
        "poc-builder": AgentDefinition(
            description=(
                "Creates pseudocode, executable, unit test, and negative PoCs for suspected "
                "vulnerabilities. Spawned by fp-check during Phase 4 verification."
            ),
            prompt=load_agent_prompt(skills_dir, "poc-builder"),
            tools=["Read", "Write", "Edit", "Grep", "Glob", "Bash"],
        ),
    }

    user_prompt = f"""\
Please verify the following security finding using the fp-check methodology.

## Finding

{finding_content}

## Instructions

The source code under review is available in your working directory.

Follow the fp-check methodology exactly as defined in your system instructions:

1. **Step 0** — Restate the vulnerability claim in your own words. Document the exact claim,
   root cause, trigger, impact, threat model, bug class, execution context, caller analysis,
   architectural context, and historical context.

2. **Route** — Choose Standard or Deep Verification based on complexity criteria.

3. **Verify** — Execute all required phases for the chosen path (data flow, exploitability,
   impact, PoC, devil's advocate).

4. **Gate Review** — Apply all six mandatory gates and the 13-item false-positive checklist.

5. **Verdict** — Deliver a final TRUE POSITIVE or FALSE POSITIVE verdict with documented evidence.

After completing your analysis, write the full verdict report to:
{output_path}
"""

    print("[audit-validator] Starting analysis...\n")

    result_text: str | None = None

    options = ClaudeAgentOptions(
        cwd=str(source_dir),
        system_prompt=system_prompt,
        allowed_tools=["Read", "Glob", "Grep", "Bash", "Write", "Agent"],
        permission_mode="acceptEdits",
        agents=agents,
        max_turns=80,
    )

    async for message in query(prompt=user_prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text, end="", flush=True)
        elif isinstance(message, ResultMessage):
            result_text = message.result
            print(f"\n\n[audit-validator] Analysis complete (stop_reason={message.stop_reason})")
        elif isinstance(message, SystemMessage) and message.subtype == "init":
            print(f"[audit-validator] Session: {message.session_id}\n")

    # Fallback: if agent didn't write the output file, write the result ourselves
    if not output_path.exists():
        if result_text:
            output_path.write_text(result_text, encoding="utf-8")
            print(f"[audit-validator] Verdict written to: {output_path}")
        else:
            print(
                "[audit-validator] Warning: no output was generated.",
                file=sys.stderr,
            )
    else:
        print(f"[audit-validator] Verdict written to: {output_path}")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate security findings with the fp-check methodology.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--finding", "-f",
        type=Path,
        required=True,
        metavar="FINDING.md",
        help="Path to the security finding markdown file.",
    )
    parser.add_argument(
        "--source", "-s",
        type=Path,
        required=True,
        metavar="SOURCE_DIR",
        help="Path to the source code directory to analyse.",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        metavar="VERDICT.md",
        help="Output path for the verdict report (default: <finding>_verdict.md).",
    )
    parser.add_argument(
        "--skills-dir",
        type=Path,
        default=None,
        metavar="SKILLS_DIR",
        help=(
            "Path to the skills marketplace directory containing the fp-check plugin "
            "(default: <script_dir>/skills)."
        ),
    )

    args = parser.parse_args()

    # Resolve skills directory
    skills_dir: Path = args.skills_dir or (Path(__file__).parent / "skills")
    skills_dir = skills_dir.resolve()

    # Validate inputs
    finding_path: Path = args.finding.resolve()
    if not finding_path.exists():
        parser.error(f"Finding file not found: {finding_path}")

    source_dir: Path = args.source.resolve()
    if not source_dir.is_dir():
        parser.error(f"Source directory not found: {source_dir}")

    fp_check_skill = skills_dir / "plugins" / "fp-check" / "skills" / "fp-check" / "SKILL.md"
    if not fp_check_skill.exists():
        parser.error(
            f"fp-check skill not found at: {fp_check_skill}\n"
            f"Make sure --skills-dir points to the skills marketplace root."
        )

    # Default output path
    output_path: Path = (
        args.output.resolve()
        if args.output
        else finding_path.parent / f"{finding_path.stem}_verdict.md"
    )

    anyio.run(
        validate_finding,
        finding_path,
        source_dir,
        output_path,
        skills_dir,
    )


if __name__ == "__main__":
    main()
