from __future__ import annotations

import logging
import os

from flask import Flask, jsonify, request
from flask_cors import CORS

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)


@app.get('/health')
def health() -> tuple[dict[str, str], int]:
    return {'status': 'ok'}, 200


@app.post('/recognize')
def recognize():
    if 'audio' not in request.files:
        return jsonify({'status': 'error', 'message': 'Missing audio'}), 400

    file = request.files['audio']

    if not file or not file.filename:
        return jsonify({'status': 'error', 'message': 'Empty file'}), 400

    logger.info('audio_received filename=%s', file.filename)

    return jsonify({
        "status": "success",
        "song": "Blinding Lights",
        "artist": "The Weeknd",
        "confidence": 0.95,
        "decision": "AUTO_ADD",
        "message": "Mock recognition successful"
    }), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
