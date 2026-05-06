from __future__ import annotations

import logging
import os
import tempfile
import time
from pathlib import Path

import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

ALLOWED_EXTENSIONS = {'.mp3', '.wav', '.m4a', '.ogg', '.flac', '.aac'}
AUDD_API_URL = 'https://api.audd.io/'


@app.get('/health')
def health() -> tuple[dict[str, str], int]:
    return {'status': 'ok'}, 200


@app.post('/recognize')
def recognize():
    start = time.perf_counter()
    temp_path: str | None = None

    if 'audio' not in request.files:
        logger.info('recognition_error reason=missing_audio')
        return jsonify({'status': 'error', 'message': 'Missing audio', 'decision': 'RETRY'}), 400

    file = request.files['audio']

    if not file or not file.filename:
        logger.info('recognition_error reason=empty_file')
        return jsonify({'status': 'error', 'message': 'Empty file', 'decision': 'RETRY'}), 400

    suffix = Path(file.filename).suffix.lower()
    if suffix not in ALLOWED_EXTENSIONS:
        logger.error('recognition_error reason=unsupported_extension filename=%s', file.filename)
        return jsonify({'status': 'error', 'message': 'Unsupported audio format', 'decision': 'RETRY'}), 400

    api_token = os.getenv('AUDD_API_TOKEN')
    if not api_token:
        logger.error('recognition_error reason=missing_audd_api_token')
        return jsonify({'status': 'error', 'message': 'AUDD_API_TOKEN is not configured', 'decision': 'RETRY'}), 500

    logger.info('audio_received filename=%s', file.filename)

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            file.save(temp_file.name)
            temp_path = temp_file.name

        with open(temp_path, 'rb') as audio_file:
            audd_response = requests.post(
                AUDD_API_URL,
                data={
                    'api_token': api_token,
                    'return': 'spotify',
                },
                files={'file': (file.filename, audio_file, file.mimetype or 'application/octet-stream')},
                timeout=15,
            )

        audd_response.raise_for_status()

        try:
            audd_payload = audd_response.json()
        except ValueError:
            logger.error('recognition_error reason=invalid_audd_json')
            return jsonify({'status': 'error', 'message': 'Invalid response from AudD', 'decision': 'RETRY'}), 502

        if audd_payload.get('status') != 'success':
            error = audd_payload.get('error')
            if isinstance(error, dict):
                message = error.get('error_message') or error.get('message') or 'AudD API error'
            elif isinstance(error, str) and error:
                message = error
            else:
                message = 'AudD API error'
            logger.error('recognition_error reason=audd_api_error message=%s', message)
            return jsonify({'status': 'error', 'message': message, 'decision': 'RETRY'}), 502

        result = audd_payload.get('result')
        if not result or not result.get('title'):
            return jsonify({
                'status': 'error',
                'song': None,
                'artist': None,
                'confidence': None,
                'decision': 'RETRY',
                'message': 'No match found',
            }), 200

        song = result.get('title')
        artist = result.get('artist')
        elapsed = round((time.perf_counter() - start) * 1000, 2)

        logger.info(
            'recognition_complete song=%s artist=%s processing_ms=%s',
            song,
            artist,
            elapsed,
        )

        return jsonify({
            'status': 'success',
            'song': song,
            'artist': artist,
            'confidence': 0.95,
            'decision': 'AUTO_ADD',
            'message': 'Recognition successful',
        }), 200

    except requests.Timeout:
        logger.error('recognition_error reason=audd_timeout')
        return jsonify({'status': 'error', 'message': 'AudD request timed out', 'decision': 'RETRY'}), 504

    except requests.RequestException as exc:
        logger.error('recognition_error reason=audd_request_failed message=%s', str(exc))
        return jsonify({'status': 'error', 'message': 'AudD request failed', 'decision': 'RETRY'}), 502

    except Exception as exc:
        logger.error('recognition_error reason=unexpected message=%s', str(exc), exc_info=True)
        return jsonify({'status': 'error', 'message': 'Recognition failed', 'decision': 'RETRY'}), 500

    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
