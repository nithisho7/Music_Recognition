from __future__ import annotations

import logging
import time
from dataclasses import asdict, dataclass
from typing import Any

from audio_processing import extract_features, preprocess_audio
from config import AUTO_ADD_THRESHOLD, CONFIRM_THRESHOLD, TOP_K_SUGGESTIONS
from logging_store import RecognitionLogStore
from matcher import Candidate, MatchResult, SongMatcher

logger = logging.getLogger(__name__)


@dataclass
class RecognitionResponse:
    status: str
    song: str | None
    artist: str | None
    confidence: float | None
    decision: str | None
    processing_time: float
    recording_time_ms: float | None
    upload_time_ms: float
    backend_processing_time_ms: float
    total_response_time_ms: float
    suggestions: list[Candidate]
    message: str | None = None

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload['suggestions'] = [asdict(suggestion) for suggestion in self.suggestions]
        return payload


class RecognitionService:
    def __init__(self, matcher: SongMatcher | None = None, log_store: RecognitionLogStore | None = None) -> None:
        self.matcher = matcher or SongMatcher()
        self.log_store = log_store or RecognitionLogStore()

    def _status_from_match(self, match: MatchResult) -> tuple[str, str | None]:
        if match.confidence >= AUTO_ADD_THRESHOLD:
            return 'success', None
        if match.confidence >= CONFIRM_THRESHOLD:
            return 'success', 'Confidence is moderate. Confirm before adding to Spotify.'
        return 'error', 'No match found with sufficient confidence.'

    def recognize(self, audio_path: str, *, recording_time_ms: float | None, upload_time_ms: float) -> RecognitionResponse:
        processing_start = time.perf_counter()

        processed_audio, sample_rate = preprocess_audio(audio_path)
        features = extract_features(processed_audio, sample_rate)
        match = self.matcher.match_features(features, top_k=TOP_K_SUGGESTIONS)

        backend_processing_time_ms = round((time.perf_counter() - processing_start) * 1000.0, 2)
        total_response_time_ms = round(upload_time_ms + backend_processing_time_ms, 2)
        processing_time = round(backend_processing_time_ms / 1000.0, 3)

        status, message = self._status_from_match(match)
        result_label = 'success' if status == 'success' else 'failure'
        self.log_store.log(
            processing_time=processing_time,
            confidence=match.confidence,
            result=result_label,
            song_name=match.song_name,
        )

        logger.info(
            'recognition_complete status=%s song=%s confidence=%.4f processing_ms=%.2f',
            status,
            match.song_name,
            match.confidence,
            backend_processing_time_ms,
        )

        return RecognitionResponse(
            status=status,
            song=match.song_name,
            artist=match.artist,
            confidence=match.confidence,
            decision=match.decision,
            processing_time=processing_time,
            recording_time_ms=recording_time_ms,
            upload_time_ms=round(upload_time_ms, 2),
            backend_processing_time_ms=backend_processing_time_ms,
            total_response_time_ms=total_response_time_ms,
            suggestions=match.suggestions,
            message=message,
        )

    def log_exception(self, processing_time: float, message: str) -> None:
        logger.exception('recognition_failed message=%s', message)
        self.log_store.log(processing_time=processing_time, confidence=None, result='failure', song_name=None)
