from __future__ import annotations

import argparse
import csv
import json
import logging
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Literal

import numpy as np

from config import (
    AUTO_ADD_THRESHOLD,
    CONFIRM_THRESHOLD,
    DATASET_DIR,
    FEATURES_DIR,
    TOP_K_SUGGESTIONS,
)
from audio_processing import extract_full_features

Decision = Literal['AUTO_ADD', 'ASK_CONFIRMATION', 'RETRY_RECORDING']
Metric = Literal['cosine', 'euclidean']

logger = logging.getLogger(__name__)
EPSILON = 1e-8
FEATURE_MATRIX_PATH = FEATURES_DIR / 'feature_matrix.npy'
LABELS_PATH = FEATURES_DIR / 'labels.json'
FEATURE_STATS_PATH = FEATURES_DIR / 'feature_stats.npz'
SONGS_CSV_PATH = DATASET_DIR / 'songs.csv'


@dataclass
class Candidate:
    song: str
    artist: str | None
    similarity: float
    confidence: float


@dataclass
class MatchResult:
    song_name: str
    artist: str | None
    similarity: float
    confidence: float
    decision: Decision
    suggestions: list[Candidate]


class SongMatcher:
    def __init__(self) -> None:
        self.feature_matrix: np.ndarray | None = None
        self.normalized_feature_matrix: np.ndarray | None = None
        self.labels: list[str] = []
        self.feature_mean: np.ndarray | None = None
        self.feature_std: np.ndarray | None = None
        self.song_metadata: dict[str, dict[str, str | None]] = {}
        self._load_feature_store()

    def _load_feature_store(self) -> None:
        if not FEATURE_MATRIX_PATH.exists():
            raise FileNotFoundError(f'Missing {FEATURE_MATRIX_PATH}. Run: python dataset/build_features.py --force')
        if not LABELS_PATH.exists():
            raise FileNotFoundError(f'Missing {LABELS_PATH}. Run: python dataset/build_features.py --force')
        if not FEATURE_STATS_PATH.exists():
            raise FileNotFoundError(f'Missing {FEATURE_STATS_PATH}. Run: python dataset/build_features.py --force')

        raw_matrix = np.load(FEATURE_MATRIX_PATH).astype(np.float32)
        stats = np.load(FEATURE_STATS_PATH)
        mean = stats['mean'].astype(np.float32)
        std = stats['std'].astype(np.float32)
        std = np.where(std < EPSILON, 1.0, std).astype(np.float32)
        labels = self._load_labels(LABELS_PATH)

        if raw_matrix.ndim != 2:
            raise ValueError(f'feature_matrix.npy must be 2D, got shape {raw_matrix.shape}')
        if raw_matrix.shape[0] != len(labels):
            raise ValueError('Feature matrix row count and labels count do not match.')
        if mean.shape != (raw_matrix.shape[1],) or std.shape != (raw_matrix.shape[1],):
            raise ValueError('Feature statistics shape mismatch. Rebuild the dataset features.')

        self.feature_matrix = raw_matrix
        self.feature_mean = mean
        self.feature_std = std
        self.normalized_feature_matrix = ((raw_matrix - mean) / std).astype(np.float32)
        self.labels = labels
        self.song_metadata = self._load_song_metadata(SONGS_CSV_PATH)
        logger.info('Loaded matcher store rows=%d dim=%d', raw_matrix.shape[0], raw_matrix.shape[1])

    def _load_labels(self, labels_path: Path) -> list[str]:
        payload = json.loads(labels_path.read_text(encoding='utf-8'))
        ordered = sorted(payload.items(), key=lambda item: int(item[0]))
        return [str(value) for _, value in ordered]

    def _load_song_metadata(self, csv_path: Path) -> dict[str, dict[str, str | None]]:
        metadata: dict[str, dict[str, str | None]] = {}
        if not csv_path.exists():
            return metadata

        with csv_path.open('r', encoding='utf-8-sig', newline='') as handle:
            sample = handle.read(2048)
            handle.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters=',\t;')
            except csv.Error:
                dialect = csv.excel_tab
            reader = csv.DictReader(handle, dialect=dialect)
            for row in reader:
                if not row:
                    continue
                song_name = (row.get('song_name') or '').strip()
                artist = (row.get('artist') or '').strip() or None
                file_path = (row.get('file_path') or '').strip()
                keys: set[str] = set()
                if song_name:
                    keys.add(song_name)
                if file_path:
                    keys.add(Path(file_path).stem)
                for key in keys:
                    metadata[key] = {'song_name': song_name or key, 'artist': artist}
        return metadata

    def _decision_from_confidence(self, confidence: float) -> Decision:
        if confidence >= AUTO_ADD_THRESHOLD:
            return 'AUTO_ADD'
        if confidence >= CONFIRM_THRESHOLD:
            return 'ASK_CONFIRMATION'
        return 'RETRY_RECORDING'

    def _candidate_confidence(self, similarity: float, metric: Metric) -> float:
        if metric == 'cosine':
            return float(np.clip((similarity + 1.0) / 2.0, 0.0, 1.0))
        return float(np.clip(similarity, 0.0, 1.0))

    def _compute_similarities(self, normalized_query: np.ndarray, metric: Metric) -> np.ndarray:
        assert self.normalized_feature_matrix is not None
        if metric == 'cosine':
            query_norm = np.linalg.norm(normalized_query)
            matrix_norms = np.linalg.norm(self.normalized_feature_matrix, axis=1)
            denom = (matrix_norms * max(query_norm, EPSILON)) + EPSILON
            return (self.normalized_feature_matrix @ normalized_query) / denom
        distances = np.linalg.norm(self.normalized_feature_matrix - normalized_query, axis=1)
        return 1.0 / (1.0 + distances)

    def _calculate_confidence(self, best: float, second: float | None, metric: Metric) -> float:
        if metric == 'cosine':
            base = (best + 1.0) / 2.0
            margin = 0.0 if second is None else max(best - second, 0.0) / 2.0
        else:
            base = max(min(best, 1.0), 0.0)
            margin = 0.0 if second is None else max(best - second, 0.0)
        confidence = 0.85 * base + 0.15 * margin
        return float(np.clip(confidence, 0.0, 1.0))

    def _metadata_for_label(self, label: str) -> tuple[str, str | None]:
        row = self.song_metadata.get(label)
        if not row:
            return label, None
        return str(row.get('song_name') or label), row.get('artist')

    def match_features(self, query_features: np.ndarray, metric: Metric = 'cosine', top_k: int = TOP_K_SUGGESTIONS) -> MatchResult:
        assert self.feature_mean is not None
        assert self.feature_std is not None

        if query_features.shape != self.feature_mean.shape:
            raise ValueError(
                f'Query feature shape {query_features.shape} does not match dataset shape {self.feature_mean.shape}'
            )

        normalized_query = ((query_features - self.feature_mean) / self.feature_std).astype(np.float32)
        similarities = self._compute_similarities(normalized_query, metric)
        sorted_indices = np.argsort(similarities)[::-1]
        top_indices = sorted_indices[:max(1, top_k)]

        suggestions: list[Candidate] = []
        for index in top_indices:
            label = self.labels[int(index)]
            song_name, artist = self._metadata_for_label(label)
            similarity = float(similarities[int(index)])
            suggestions.append(
                Candidate(
                    song=song_name,
                    artist=artist,
                    similarity=similarity,
                    confidence=self._candidate_confidence(similarity, metric),
                )
            )

        best = suggestions[0]
        second_similarity = suggestions[1].similarity if len(suggestions) > 1 else None
        confidence = self._calculate_confidence(best.similarity, second_similarity, metric)
        decision = self._decision_from_confidence(confidence)

        logger.info(
            'best_match=%s similarity=%.4f confidence=%.4f decision=%s',
            best.song,
            best.similarity,
            confidence,
            decision,
        )

        return MatchResult(
            song_name=best.song,
            artist=best.artist,
            similarity=best.similarity,
            confidence=confidence,
            decision=decision,
            suggestions=suggestions,
        )

    def match_query_audio(self, query_audio_path: str, metric: Metric = 'cosine', top_k: int = TOP_K_SUGGESTIONS) -> MatchResult:
        query_features = extract_full_features(query_audio_path)
        return self.match_features(query_features, metric=metric, top_k=top_k)


MATCHER = SongMatcher()


def match_query_audio(query_audio_path: str, metric: Metric = 'cosine', top_k: int = TOP_K_SUGGESTIONS) -> MatchResult:
    return MATCHER.match_query_audio(query_audio_path, metric=metric, top_k=top_k)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Match query audio to precomputed song features.')
    parser.add_argument('query_audio', help='Path to query .wav/.mp3 file')
    parser.add_argument('--metric', choices=['cosine', 'euclidean'], default='cosine')
    parser.add_argument('--top-k', type=int, default=TOP_K_SUGGESTIONS)
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
    args = parse_args()
    result = MATCHER.match_query_audio(args.query_audio, metric=args.metric, top_k=args.top_k)
    print(json.dumps(asdict(result), indent=2))


if __name__ == '__main__':
    main()
