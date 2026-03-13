#!/usr/bin/env python3
"""Rename finding files to random names and create labels.json."""

import argparse
import json
import uuid
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Rename finding files to random names and store labels separately."
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without renaming")
    parser.add_argument("--dataset-dir", default="./dataset", help="Path to dataset directory")
    args = parser.parse_args()

    dataset_dir = Path(args.dataset_dir)
    if not dataset_dir.exists():
        print(f"Dataset directory not found: {dataset_dir}")
        return

    labels = {}
    renames = []

    for old_path in sorted(dataset_dir.rglob("*.json")):
        if old_path.name.endswith(".result.json"):
            continue
        if "src" in old_path.parts:
            continue
        if old_path.name in ("dataset_info.json", "labels.json"):
            continue

        fname = old_path.stem
        if fname.startswith("tp_"):
            label = "tp"
        elif fname.startswith("fp_"):
            label = "fp"
        else:
            continue

        # Cross-check with triage_verdict
        try:
            data = json.loads(old_path.read_text())
            verdict = data.get("triage_verdict")
            expected = "valid" if label == "tp" else "invalid"
            if verdict and verdict != expected:
                print(f"WARNING: {old_path} has label={label} but triage_verdict={verdict}")
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: Could not read {old_path}: {e}")

        # Generate unique random name
        new_name = uuid.uuid4().hex[:12] + ".json"
        new_path = old_path.parent / new_name
        rel_path = str(new_path.relative_to(dataset_dir))
        labels[rel_path] = label

        renames.append((old_path, new_path))

    if args.dry_run:
        print(f"Would rename {len(renames)} finding(s):\n")
        for old, new in renames:
            print(f"  {old.relative_to(dataset_dir)} -> {new.name}")
            old_result = old.with_suffix(".result.json")
            if old_result.exists():
                new_result = new.with_suffix(".result.json")
                print(f"  {old_result.relative_to(dataset_dir)} -> {new_result.name}")
        print(f"\nWould write labels.json with {len(labels)} entries")
        return

    for old_path, new_path in renames:
        old_path.rename(new_path)
        # Rename .result.json if it exists
        old_result = old_path.with_suffix(".result.json")
        if old_result.exists():
            new_result = new_path.with_suffix(".result.json")
            old_result.rename(new_result)

    labels_path = dataset_dir / "labels.json"
    labels_path.write_text(json.dumps(labels, indent=2, sort_keys=True) + "\n")

    print(f"Renamed {len(renames)} finding(s). Labels written to {labels_path}")


if __name__ == "__main__":
    main()
