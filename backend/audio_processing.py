from __future__ import annotations

import numpy as np
import librosa  # pyright: ignore[reportMissingImports]

from config import DEFAULT_SAMPLE_RATE, TARGET_DURATION_SECONDS, TRIM_TOP_DB

EPSILON = 1e-8


def _to_mono(y: np.ndarray) -> np.ndarray:
    if y.ndim == 1:
        return y.astype(np.float32)
    return librosa.to_mono(y).astype(np.float32)


def _trim_silence(y: np.ndarray, sr: int, top_db: int = TRIM_TOP_DB) -> np.ndarray:
    # Silence trimming reduces long quiet tails that otherwise dominate summary features.
    trimmed, _ = librosa.effects.trim(y, top_db=top_db)
    return trimmed if trimmed.size else y


def _normalize_volume(y: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    if peak <= EPSILON:
        return y.astype(np.float32)
    return (y / peak).astype(np.float32)


def _resample_audio(y: np.ndarray, orig_sr: int, target_sr: int = DEFAULT_SAMPLE_RATE) -> tuple[np.ndarray, int]:
    if orig_sr == target_sr:
        return y.astype(np.float32), target_sr
    resampled = librosa.resample(y, orig_sr=orig_sr, target_sr=target_sr)
    return resampled.astype(np.float32), target_sr


def _standardize_duration(y: np.ndarray, sr: int, target_seconds: float = TARGET_DURATION_SECONDS) -> np.ndarray:
    # Matching is more stable when every clip covers the same time window.
    target_len = int(target_seconds * sr)
    if target_len <= 0 or len(y) == target_len:
        return y.astype(np.float32)
    if len(y) > target_len:
        start = (len(y) - target_len) // 2
        return y[start:start + target_len].astype(np.float32)
    return np.pad(y, (0, target_len - len(y)), mode='constant').astype(np.float32)


def preprocess_audio(audio_path: str) -> tuple[np.ndarray, int]:
    y, sr = librosa.load(audio_path, sr=16000, mono=True)
    y = _to_mono(y)
    y = _trim_silence(y, sr)
    y = _normalize_volume(y)
    y, sr = _resample_audio(y, sr, DEFAULT_SAMPLE_RATE)
    y = _standardize_duration(y, sr, TARGET_DURATION_SECONDS)
    return y.astype(np.float32), int(sr)


def extract_features(y: np.ndarray, sr: int, n_mfcc: int = 13) -> np.ndarray:
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
    mfcc_mean = np.mean(mfcc, axis=1)
    mfcc_std = np.std(mfcc, axis=1)

    centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
    bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
    zcr = librosa.feature.zero_crossing_rate(y)

    spectral_mean = np.array(
        [np.mean(centroid), np.mean(rolloff), np.mean(bandwidth), np.mean(zcr)],
        dtype=np.float32,
    )
    spectral_std = np.array(
        [np.std(centroid), np.std(rolloff), np.std(bandwidth), np.std(zcr)],
        dtype=np.float32,
    )

    chroma = librosa.feature.chroma_stft(y=y, sr=sr)
    chroma_mean = np.mean(chroma, axis=1)
    chroma_std = np.std(chroma, axis=1)

    return np.concatenate(
        [mfcc_mean, mfcc_std, spectral_mean, spectral_std, chroma_mean, chroma_std],
        axis=0,
    ).astype(np.float32)


def extract_mean_mfcc(audio_path: str, n_mfcc: int = 13) -> np.ndarray:
    y, sr = preprocess_audio(audio_path)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
    return np.mean(mfcc, axis=1).astype(np.float32)


def extract_full_features(audio_path: str, n_mfcc: int = 13) -> np.ndarray:
    y, sr = preprocess_audio(audio_path)
    return extract_features(y, sr, n_mfcc=n_mfcc)


if __name__ == '__main__':
    test_audio_path = 'dataset/songs/hey.mp3'
    processed, sample_rate = preprocess_audio(test_audio_path)
    feature_vector = extract_features(processed, sample_rate)
    print('Sample rate:', sample_rate)
    print('Processed samples:', processed.shape)
    print('Feature shape:', feature_vector.shape)
