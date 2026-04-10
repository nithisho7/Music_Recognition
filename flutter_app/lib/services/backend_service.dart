import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../models/recognition_result.dart';

class BackendService {
  BackendService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<RecognitionResult> recognize({
    required String audioPath,
    required int recordingTimeMs,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(AppConfig.backendRecognizeUrl));
    request.fields['recording_time_ms'] = recordingTimeMs.toString();
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

    final uploadStopwatch = Stopwatch()..start();
    final streamed = await request.send().timeout(
      const Duration(seconds: AppConfig.networkTimeoutSeconds),
    );
    final response = await http.Response.fromStream(streamed);
    uploadStopwatch.stop();

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Backend returned an invalid response.');
    }

    final result = RecognitionResult.fromJson(
      decoded,
      fallbackUploadTimeMs: uploadStopwatch.elapsedMilliseconds.toDouble(),
    );

    if (response.statusCode >= 500) {
      throw Exception(result.message ?? 'Backend failed to process the audio.');
    }

    return result;
  }

  void dispose() {
    _client.close();
  }
}
