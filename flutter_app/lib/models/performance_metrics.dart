class PerformanceMetrics {
  const PerformanceMetrics({
    required this.recordingTimeMs,
    required this.uploadTimeMs,
    required this.backendProcessingTimeMs,
    required this.totalResponseTimeMs,
    required this.processingTimeSeconds,
  });

  final double? recordingTimeMs;
  final double uploadTimeMs;
  final double backendProcessingTimeMs;
  final double totalResponseTimeMs;
  final double processingTimeSeconds;

  factory PerformanceMetrics.fromJson(Map<String, dynamic> json, {double? fallbackUploadTimeMs}) {
    return PerformanceMetrics(
      recordingTimeMs: (json['recording_time_ms'] as num?)?.toDouble(),
      uploadTimeMs: (json['upload_time_ms'] as num?)?.toDouble() ?? fallbackUploadTimeMs ?? 0.0,
      backendProcessingTimeMs: (json['backend_processing_time_ms'] as num?)?.toDouble() ?? 0.0,
      totalResponseTimeMs: (json['total_response_time_ms'] as num?)?.toDouble() ?? 0.0,
      processingTimeSeconds: (json['processing_time'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
