#!/usr/bin/env python3
"""Summarize validation results as a confusion matrix."""

import json
import sys
from pathlib import Path

def main():
    dataset_dir = Path(__file__).parent / "dataset"
    if not dataset_dir.exists():
        print(f"Dataset directory not found: {dataset_dir}")
        sys.exit(1)

    # Confusion matrix: [predicted][actual]
    # Real: tp_ prefix = actually valid, fp_ prefix = actually invalid
    # Predicted: is_valid=True = predicted valid, is_valid=False = predicted invalid
    tp_as_tp = 0  # real=TP, predicted=valid (correct)
    tp_as_fp = 0  # real=TP, predicted=invalid (miss)
    fp_as_tp = 0  # real=FP, predicted=valid (miss)
    fp_as_fp = 0  # real=FP, predicted=invalid (correct)

    for result_file in dataset_dir.rglob("*.result.json"):
        fname = result_file.stem.replace(".result", "")
        is_tp = fname.startswith("tp_")
        is_fp = fname.startswith("fp_")
        if not (is_tp or is_fp):
            continue

        try:
            data = json.loads(result_file.read_text())
        except (json.JSONDecodeError, OSError):
            continue

        predicted_valid = data.get("is_valid")

        if is_tp and predicted_valid is True:
            tp_as_tp += 1
        elif is_tp and predicted_valid is False:
            tp_as_fp += 1
        elif is_fp and predicted_valid is True:
            fp_as_tp += 1
        elif is_fp and predicted_valid is False:
            fp_as_fp += 1

    total = tp_as_tp + tp_as_fp + fp_as_tp + fp_as_fp

    print()
    print("                  Confusion Matrix")
    print()
    print("                        Real Label")
    print("                  TP (valid)   FP (invalid)")
    print("                ┌────────────┬────────────┐")
    print(f"  Predicted  TP │ {tp_as_tp:>6}     │ {fp_as_tp:>6}     │")
    print(f"  (is_valid) ── │  (hit)     │  (miss)    │")
    print("                ├────────────┼────────────┤")
    print(f"             FP │ {tp_as_fp:>6}     │ {fp_as_fp:>6}     │")
    print(f"             ── │  (miss)    │  (hit)     │")
    print("                └────────────┴────────────┘")
    print()
    accuracy = (tp_as_tp + fp_as_fp) / total * 100
    precision = tp_as_tp / (tp_as_tp + fp_as_tp) * 100 if (tp_as_tp + fp_as_tp) else 0
    recall = tp_as_tp / (tp_as_tp + tp_as_fp) * 100 if (tp_as_tp + tp_as_fp) else 0

    print(f"  Total: {total}    Accuracy:  {accuracy:.1f}%")
    print(f"                Precision: {precision:.1f}%")
    print(f"                Recall:    {recall:.1f}%")
    print()

if __name__ == "__main__":
    main()
