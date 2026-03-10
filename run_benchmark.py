#!/usr/bin/env python3
"""Run benchmark findings through codex_validate.

Results are cached in benchmark/results/ to avoid re-running completed findings.

Usage:
    # Run all findings
    python run_benchmark.py

    # Run a single finding
    python run_benchmark.py --finding benchmark/dataset/Anome/tp_finding_01.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import codex_validate

DATASET_DIR = Path(__file__).resolve().parent / "benchmark" / "dataset"
SOURCE_ROOT = Path(__file__).resolve().parent / "benchmark" / "source_code"
RESULTS_DIR = Path(__file__).resolve().parent / "benchmark" / "results"
VALIDATOR = "codex"

_TP_PATTERN = re.compile(r"\bTRUE[_\s-]?POSITIVE\b", re.IGNORECASE)
_FP_PATTERN = re.compile(r"\bFALSE[_\s-]?POSITIVE\b", re.IGNORECASE)
_VALID_VERDICTS = {"valid", "verified_as_valid"}
_INVALID_VERDICTS = {"invalid", "verified_as_invalid"}


def derive_source_dir(local_file_path: str) -> Path | None:
    marker = "/source_code/"
    idx = local_file_path.find(marker)
    if idx == -1:
        return None
    parts = [p for p in local_file_path[idx + len(marker):].split("/") if p]
    if not parts:
        return None
    depth = 3 if parts[0].lower() == "bsc" else 4
    if len(parts) < depth:
        return None
    return SOURCE_ROOT.joinpath(*parts[:depth])


def normalise_verdict(v: str | None) -> str | None:
    if not v:
        return None
    if v.lower() in _VALID_VERDICTS:
        return "tp"
    if v.lower() in _INVALID_VERDICTS:
        return "fp"
    return None


def parse_verdict(text: str) -> str | None:
    tp = len(_TP_PATTERN.findall(text))
    fp = len(_FP_PATTERN.findall(text))
    if tp > fp:
        return "tp"
    if fp > tp:
        return "fp"
    return None


def result_path(finding: Path) -> Path:
    rel = finding.relative_to(DATASET_DIR)
    return RESULTS_DIR / VALIDATOR / rel.with_suffix(".result.json")


def load_result(finding: Path) -> dict | None:
    p = result_path(finding)
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            pass
    return None


def save_result(finding: Path, data: dict) -> None:
    p = result_path(finding)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2), encoding="utf-8")


def run_codex(source_dir: Path, finding: Path) -> tuple[int, str]:
    rc = codex_validate.main([str(source_dir), str(finding)])
    return rc, ""


def run_finding(finding: Path) -> dict:
    """Run a single finding through the validator; return result dict."""
    cached = load_result(finding)
    if cached:
        print(f"  CACHED  [{VALIDATOR.upper()}] {finding.relative_to(DATASET_DIR)}")
        return cached

    data = json.loads(finding.read_text(encoding="utf-8"))
    local_file_path = (
        data.get("location", {}).get("local_file_path")
        or data.get("local_file_path")
        or ""
    )
    raw_verdict = data.get("triage_verdict") or data.get("status", "")
    expected = "tp" if finding.stem.startswith("tp_") else "fp"
    ground_truth = normalise_verdict(raw_verdict) or expected
    source_dir = derive_source_dir(local_file_path) if local_file_path else None

    label = f"[{VALIDATOR.upper()}] {finding.relative_to(DATASET_DIR)}"

    if source_dir is None or not source_dir.is_dir():
        print(f"  SKIP    {label}  (source dir not found)")
        result = {"validator": VALIDATOR, "finding": str(finding.relative_to(DATASET_DIR.parent)),
                  "ground_truth": ground_truth, "predicted": None, "correct": None,
                  "error": f"source dir not found: {source_dir}", "duration_s": 0.0}
        save_result(finding, result)
        return result

    print(f"  RUN     {label}  (gt={ground_truth.upper()}) ...", flush=True)

    t0 = time.monotonic()
    try:
        rc, output = run_codex(source_dir, finding)
    except Exception as exc:
        rc, output = 1, str(exc)
    dur = time.monotonic() - t0

    predicted = parse_verdict(output)
    correct = (predicted == ground_truth) if predicted is not None else None
    status = "???" if correct is None else ("PASS" if correct else "FAIL")
    print(f"  {status}     {label}  predicted={predicted.upper() if predicted else 'N/A'} "
          f"gt={ground_truth.upper()}  ({dur:.1f}s)")

    result = {"validator": VALIDATOR, "finding": str(finding.relative_to(DATASET_DIR.parent)),
              "ground_truth": ground_truth, "predicted": predicted, "correct": correct,
              "returncode": rc, "duration_s": dur, "output": output}
    save_result(finding, result)
    return result


def print_summary(results: list[dict]) -> None:
    total = len(results)
    correct = sum(1 for r in results if r["correct"] is True)
    tp = [r for r in results if r["ground_truth"] == "tp"]
    fp = [r for r in results if r["ground_truth"] == "fp"]
    tp_correct = sum(1 for r in tp if r["correct"] is True)
    fp_correct = sum(1 for r in fp if r["correct"] is True)
    print(f"\n{'='*50}")
    print(f"  {VALIDATOR.upper()}  |  {correct}/{total} correct  ({correct/total:.1%})")
    print(f"  TP recall: {tp_correct}/{len(tp)}  FP recall: {fp_correct}/{len(fp)}")
    print(f"{'='*50}\n")


def discover_findings() -> list[Path]:
    findings = []
    for dataset_dir in sorted(DATASET_DIR.iterdir()):
        if not dataset_dir.is_dir():
            continue
        for pattern in ("tp_finding_*.json", "fp_finding_*.json"):
            findings.extend(sorted(dataset_dir.glob(pattern)))
    return findings


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--finding", type=Path, default=None,
                   help="Path to a single finding JSON file. Omit to run all findings.")
    args = p.parse_args(argv)

    findings = [args.finding.resolve()] if args.finding else discover_findings()
    if not findings:
        print("No findings found.", file=sys.stderr)
        return 1

    results = [run_finding(f) for f in findings]
    if len(findings) > 1:
        print_summary(results)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
