from __future__ import annotations

import argparse
from pathlib import Path

from audio_processing import extract_features, preprocess_audio
from matcher import SongMatcher


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Evaluate recognition quality on dataset songs.')
    parser.add_argument('--songs-dir', default='dataset/songs', help='Path to dataset songs directory')
    parser.add_argument('--metric', choices=['cosine', 'euclidean'], default='cosine')
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    songs_dir = Path(args.songs_dir)
    if not songs_dir.exists():
        print(f'Songs folder not found: {songs_dir}')
        return

    matcher = SongMatcher()
    audio_files = [path for path in sorted(songs_dir.iterdir()) if path.is_file() and path.suffix.lower() in {'.mp3', '.wav'}]
    if not audio_files:
        print('No songs found for evaluation.')
        return

    total = 0
    correct = 0
    failures = 0
    confidence_sum = 0.0
    incorrect: list[str] = []

    for audio_path in audio_files:
        expected = audio_path.stem
        processed_audio, sample_rate = preprocess_audio(str(audio_path))
        features = extract_features(processed_audio, sample_rate)
        result = matcher.match_features(features, metric=args.metric)

        total += 1
        confidence_sum += result.confidence
        if result.decision == 'RETRY_RECORDING':
            failures += 1

        if result.song_name == expected:
            correct += 1
        else:
            incorrect.append(
                f'- expected={expected} predicted={result.song_name} confidence={result.confidence:.4f}'
            )

    accuracy = correct / total if total else 0.0
    average_confidence = confidence_sum / total if total else 0.0
    failure_rate = failures / total if total else 0.0

    print('Evaluation summary')
    print(f'Total songs        : {total}')
    print(f'Accuracy           : {accuracy:.4f} ({accuracy * 100:.2f}%)')
    print(f'Average confidence : {average_confidence:.4f}')
    print(f'Failure rate       : {failure_rate:.4f} ({failure_rate * 100:.2f}%)')
    print(f'Incorrect matches  : {len(incorrect)}')
    if incorrect:
        print('\nIncorrect details')
        for line in incorrect:
            print(line)


if __name__ == '__main__':
    main()
