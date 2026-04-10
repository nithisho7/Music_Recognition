class SongSuggestion {
  const SongSuggestion({
    required this.song,
    required this.artist,
    required this.confidence,
    required this.similarity,
  });

  final String song;
  final String? artist;
  final double confidence;
  final double similarity;

  String get subtitle {
    if (artist == null || artist!.isEmpty) {
      return '${(confidence * 100).toStringAsFixed(1)}% confidence';
    }
    return '$artist • ${(confidence * 100).toStringAsFixed(1)}% confidence';
  }

  factory SongSuggestion.fromJson(Map<String, dynamic> json) {
    return SongSuggestion(
      song: json['song'] as String? ?? 'Unknown Song',
      artist: json['artist'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
