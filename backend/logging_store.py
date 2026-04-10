from __future__ import annotations

import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from config import LOG_DB_PATH


class RecognitionLogStore:
    def __init__(self, db_path: Path = LOG_DB_PATH) -> None:
        self.db_path = db_path
        self._initialize()

    def _initialize(self) -> None:
        with closing(sqlite3.connect(self.db_path)) as conn:
            conn.execute(
                '''
                CREATE TABLE IF NOT EXISTS recognition_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    processing_time REAL NOT NULL,
                    confidence REAL,
                    result TEXT NOT NULL,
                    song_name TEXT
                )
                '''
            )
            conn.commit()

    def log(self, *, processing_time: float, confidence: float | None, result: str, song_name: str | None) -> None:
        with closing(sqlite3.connect(self.db_path)) as conn:
            conn.execute(
                '''
                INSERT INTO recognition_logs (timestamp, processing_time, confidence, result, song_name)
                VALUES (?, ?, ?, ?, ?)
                ''',
                (
                    datetime.now(timezone.utc).isoformat(),
                    processing_time,
                    confidence,
                    result,
                    song_name,
                ),
            )
            conn.commit()
