from __future__ import annotations

import logging
import os
import tempfile
import time
from pathlib import Path

from flask import Flask, jsonify, request
from flask_cors import CORS

from config import ALLOWED_EXTENSIONS
from recognition_service import RecognitionService

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
logger = logging.getLogger(__name__)
service = RecognitionService()

app = Flask(__name__)
CORS(app)


def _allowed_file(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


def _parse_optional_float(value: str | None) -> float | None:
    if value is None or value == '':
        return None
    try:
        return float(value)
    except ValueError:
        return None


@app.get('/health')
def health() -> tuple[dict[str, str], int]:
    return {'status': 'ok'}, 200


@app.post('/recognize')
def recognize():
    request_start = time.perf_counter()

    if 'audio' not in request.files:
        return jsonify({'status': 'error', 'message': 'Missing file field: audio'}), 400

    file = request.files['audio']
    if not file or not file.filename:
        return jsonify({'status': 'error', 'message': 'No file uploaded'}), 400

    if not _allowed_file(file.filename):
        return jsonify({'status': 'error', 'message': 'Unsupported audio format'}), 400

    suffix = Path(file.filename).suffix.lower()
    temp_path: str | None = None

    logger.info('audio_received filename=%s', file.filename)

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            file.save(temp_file.name)
            temp_path = temp_file.name

        upload_time_ms = round((time.perf_counter() - request_start) * 1000.0, 2)
        recording_time_ms = _parse_optional_float(request.form.get('recording_time_ms'))
        response = service.recognize(
            temp_path,
            recording_time_ms=recording_time_ms,
            upload_time_ms=upload_time_ms,
        )
        payload = response.to_dict()
        return jsonify(payload), 200

    except Exception as exc:
        elapsed = round(time.perf_counter() - request_start, 3)
        service.log_exception(processing_time=elapsed, message=str(exc))
        return jsonify({'status': 'error', 'message': str(exc)}), 500

    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
