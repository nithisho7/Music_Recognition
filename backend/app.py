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

AUDD_API_URL = os.getenv('AUDD_API_URL', 'https://api.audd.io/')
AUDD_API_TOKEN = os.getenv('AUDD_API_TOKEN')
ALLOWED_EXTENSIONS = {'.mp3', '.wav', '.m4a', '.ogg', '.flac', '.aac'}


def _allowed_file(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


@app.get('/health')
def health() -> tuple[dict[str, str], int]:
    return {'status': 'ok'}, 200


@app.post('/recognize')
def recognize():
    start = time.perf_counter()

    if not AUDD_API_TOKEN:
        logger.error('recognition_config_error missing_audd_api_token=true')
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'AudD API token is not configured.',
        }), 500

    if 'audio' not in request.files:
        logger.info('recognition_bad_request reason=missing_audio_field')
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'Missing file field: audio',
        }), 400

    file = request.files['audio']
    if not file or not file.filename:
        logger.info('recognition_bad_request reason=empty_upload')
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'No file uploaded',
        }), 400

    if not _allowed_file(file.filename):
        logger.info('recognition_bad_request reason=unsupported_format filename=%s', file.filename)
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'Unsupported audio format',
        }), 400

    suffix = Path(file.filename).suffix.lower()
    temp_path: str | None = None

    logger.info('audio_received filename=%s', file.filename)

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            file.save(temp_file.name)
            temp_path = temp_file.name

        with open(temp_path, 'rb') as audio_file:
            audd_response = requests.post(
                AUDD_API_URL,
                data={'api_token': AUDD_API_TOKEN},
                files={'file': (file.filename, audio_file, file.mimetype or 'application/octet-stream')},
                timeout=15,
            )

        audd_response.raise_for_status()
        audd_payload = audd_response.json()

        if audd_payload.get('status') != 'success':
            error = audd_payload.get('error')
            if isinstance(error, dict):
                message = error.get('error_message') or error.get('message') or 'AudD API returned an error.'
            elif isinstance(error, str) and error:
                message = error
            else:
                message = 'AudD API returned an error.'
            logger.error('recognition_provider_error provider=audd message=%s payload=%s', message, audd_payload)
            return jsonify({
                'status': 'error',
                'song': None,
                'artist': None,
                'confidence': None,
                'decision': 'RETRY',
                'message': message,
            }), 502

        result = audd_payload.get('result')
        if not result or not result.get('title'):
            logger.info('recognition_no_result')
            return jsonify({
                'status': 'error',
                'song': None,
                'artist': None,
                'confidence': None,
                'decision': 'RETRY',
                'message': 'No match found. Try again.',
            }), 200

        song = result.get('title')
        artist = result.get('artist')
        elapsed = round((time.perf_counter() - start) * 1000, 2)

        logger.info(
            'recognition_complete song=%s artist=%s time=%sms',
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
            'message': 'Song recognized.',
        }), 200

    except requests.Timeout:
        logger.error('recognition_error reason=audd_timeout')
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'AudD API request timed out. Please retry.',
        }), 504

    except ValueError as exc:
        logger.error('recognition_error reason=invalid_audd_json message=%s', str(exc), exc_info=True)
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'AudD API returned invalid JSON.',
        }), 502

    except requests.RequestException as exc:
        logger.error('recognition_error reason=audd_request_failed message=%s', str(exc), exc_info=True)
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'Unable to reach AudD API. Please retry.',
        }), 502

    except Exception as exc:
        logger.error('recognition_error reason=unexpected message=%s', str(exc), exc_info=True)
        return jsonify({
            'status': 'error',
            'song': None,
            'artist': None,
            'confidence': None,
            'decision': 'RETRY',
            'message': 'Recognition failed unexpectedly.',
        }), 500

    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
