from __future__ import annotations

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATASET_DIR = BASE_DIR / "dataset"
FEATURES_DIR = BASE_DIR / "features"
LOG_DB_PATH = BASE_DIR / "recognition_logs.db"

DEFAULT_SAMPLE_RATE = 16000
TARGET_DURATION_SECONDS = 10.0
TRIM_TOP_DB = 25
AUTO_ADD_THRESHOLD = 0.80
CONFIRM_THRESHOLD = 0.50
TOP_K_SUGGESTIONS = 3
ALLOWED_EXTENSIONS = {".mp3", ".wav", ".webm", ".ogg", ".m4a"}
