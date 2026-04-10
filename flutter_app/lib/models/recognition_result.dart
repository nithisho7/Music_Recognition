import 'performance_metrics.dart';
import 'song_suggestion.dart';

class RecognitionResult {
  const RecognitionResult({
    required this.status,
    required this.song,
    required this.artist,
    required this.confidence,
    required this.decision,
    required this.message,
    required this.metrics,
    required this.suggestions,
  });

  final String status;
  final String? song;
  final String? artist;
  final double? confidence;
  final String? decision;
  final String? message;
  final PerformanceMetrics metrics;
  final List<SongSuggestion> suggestions;

  SongSuggestion? get primarySuggestion {
    if (song != null) {
      return SongSuggestion(
        song: song!,
        artist: artist,
        confidence: confidence ?? 0.0,
        similarity: confidence ?? 0.0,
      );
    }
    if (suggestions.isEmpty) {
      return null;
    }
    return suggestions.first;
  }

  bool get isSuccessful => status == 'success';
  bool get needsConfirmation => decision == 'ASK_CONFIRMATION';
  bool get shouldRetry => decision == 'RETRY_RECORDING' || status == 'error';

  factory RecognitionResult.fromJson(Map<String, dynamic> json, {double? fallbackUploadTimeMs}) {
    final suggestionsJson = (json['suggestions'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

    return RecognitionResult(
      status: json['status'] as String? ?? 'error',
      song: json['song'] as String?,
      artist: json['artist'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      decision: json['decision'] as String?,
      message: json['message'] as String?,
      metrics: PerformanceMetrics.fromJson(json, fallbackUploadTimeMs: fallbackUploadTimeMs),
      suggestions: suggestionsJson.map(SongSuggestion.fromJson).toList(growable: false),
    );
  }
}
