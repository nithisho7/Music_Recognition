class SpotifyActionResult {
  const SpotifyActionResult({required this.success, required this.message});

  final bool success;
  final String message;

  factory SpotifyActionResult.success(String message) {
    return SpotifyActionResult(success: true, message: message);
  }

  factory SpotifyActionResult.failure(String message) {
    return SpotifyActionResult(success: false, message: message);
  }
}
