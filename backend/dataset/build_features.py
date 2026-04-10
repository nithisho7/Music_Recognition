from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from audio_processing import extract_full_features

FEATURE_DIM = 58
EPSILON = 1e-8


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and cache song feature matrix + stats.")
    parser.add_argument("--force", action="store_true", help="Rebuild artifacts even if they already exist.")
    return parser.parse_args()


def _write_atomic_npy(path: Path, array: np.ndarray) -> None:
    temp_path = path.parent / f"{path.name}.tmp"
    with temp_path.open("wb") as handle:
        np.save(handle, array)
    temp_path.replace(path)


def _write_atomic_json(path: Path, payload: dict[str, str]) -> None:
    temp_path = path.parent / f"{path.name}.tmp"
    temp_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temp_path.replace(path)


def _write_atomic_stats(path: Path, mean: np.ndarray, std: np.ndarray) -> None:
    temp_path = path.parent / f"{path.name}.tmp"
    with temp_path.open("wb") as handle:
        np.savez(handle, mean=mean, std=std)
    temp_path.replace(path)


def main() -> None:
    args = parse_args()
    start = time.time()

    songs_dir = PROJECT_ROOT / "dataset" / "songs"
    features_dir = PROJECT_ROOT / "features"

    feature_matrix_path = features_dir / "feature_matrix.npy"
    labels_path = features_dir / "labels.json"
    stats_path = features_dir / "feature_stats.npz"

    if not songs_dir.exists():
        print(f"Songs folder not found: {songs_dir}")
        return

    features_dir.mkdir(parents=True, exist_ok=True)

    if not args.force and feature_matrix_path.exists() and labels_path.exists() and stats_path.exists():
        print("Feature artifacts already exist. Use --force to rebuild.")
        return

    audio_extensions = {".mp3", ".wav"}
    audio_files = [
        path
        for path in sorted(songs_dir.iterdir())
        if path.is_file() and path.suffix.lower() in audio_extensions
    ]

    total = len(audio_files)
    processed = 0
    errors = 0

    feature_rows: list[np.ndarray] = []
    labels: dict[str, str] = {}

    for audio_path in audio_files:
        print(f"Processing: {audio_path.name}")

        try:
            features = extract_full_features(str(audio_path))
            if features.shape != (FEATURE_DIM,):
                raise ValueError(f"Unexpected feature shape {features.shape}, expected ({FEATURE_DIM},)")

            row_index = len(feature_rows)
            feature_rows.append(features.astype(np.float32))
            labels[str(row_index)] = audio_path.stem
            processed += 1
        except Exception as exc:
            errors += 1
            print(f"Error processing {audio_path.name}: {exc}")

    if not feature_rows:
        print("No valid features extracted. Build aborted.")
        return

    matrix = np.vstack(feature_rows).astype(np.float32)
    mean = matrix.mean(axis=0).astype(np.float32)
    std = matrix.std(axis=0).astype(np.float32)
    std = np.where(std < EPSILON, 1.0, std).astype(np.float32)

    try:
        _write_atomic_npy(feature_matrix_path, matrix)
        _write_atomic_json(labels_path, labels)
        _write_atomic_stats(stats_path, mean, std)
    except Exception as exc:
        print(f"Error saving artifacts: {exc}")
        return

    # Remove legacy per-song .npy vectors after successful matrix build.
    for npy_file in features_dir.glob("*.npy"):
        if npy_file.name != "feature_matrix.npy":
            npy_file.unlink(missing_ok=True)

    elapsed = time.time() - start

    print("\nBuild summary")
    print(f"Total songs        : {total}")
    print(f"Processed songs    : {processed}")
    print(f"Errors             : {errors}")
    print(f"Feature matrix     : {feature_matrix_path}")
    print(f"Labels             : {labels_path}")
    print(f"Feature statistics : {stats_path}")
    print(f"Runtime(s)         : {elapsed:.2f}")


if __name__ == "__main__":
    main()
