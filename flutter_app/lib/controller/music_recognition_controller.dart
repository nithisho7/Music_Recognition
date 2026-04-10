import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/app_state.dart';
import '../core/app_config.dart';
import '../models/recognition_result.dart';
import '../models/song_suggestion.dart';
import '../models/spotify_action_result.dart';
import '../services/audio_capture_service.dart';
import '../services/backend_service.dart';
import '../services/spotify_auth_service.dart';
import '../services/spotify_playlist_service.dart';

class MusicRecognitionController extends ChangeNotifier {
  MusicRecognitionController({
    AudioCaptureService? audioCaptureService,
    BackendService? backendService,
    SpotifyAuthService? spotifyAuthService,
    SpotifyPlaylistService? spotifyPlaylistService,
  })  : _audioCaptureService = audioCaptureService ?? AudioCaptureService(),
        _backendService = backendService ?? BackendService(),
        _spotifyAuthService = spotifyAuthService ?? SpotifyAuthService(),
        _spotifyPlaylistService = spotifyPlaylistService ?? SpotifyPlaylistService();

  final AudioCaptureService _audioCaptureService;
  final BackendService _backendService;
  final SpotifyAuthService _spotifyAuthService;
  final SpotifyPlaylistService _spotifyPlaylistService;

  AppState appState = AppState.idle;
  int secondsRemaining = AppConfig.recordingSeconds;
  String errorMessage = '';
  RecognitionResult? recognitionResult;
  SongSuggestion? selectedSuggestion;
  SpotifyActionResult? spotifyActionResult;

  Timer? _recordingTimer;
  String? _recordingPath;
  DateTime? _recordingStartedAt;

  SongSuggestion? get primarySuggestion {
    final result = recognitionResult;
    if (result == null) {
      return null;
    }
    if (selectedSuggestion != null) {
      return selectedSuggestion;
    }
    return result.primarySuggestion;
  }

  List<SongSuggestion> get topSuggestions {
    return recognitionResult?.suggestions ?? const <SongSuggestion>[];
  }

  Future<void> startListening() async {
    if (appState == AppState.listening || appState == AppState.processing) {
      return;
    }

    final granted = await _audioCaptureService.ensurePermission();
    if (!granted) {
      _setError('Microphone permission is required to recognize a song.');
      return;
    }

    _clearTransientState();
    appState = AppState.listening;
    secondsRemaining = AppConfig.recordingSeconds;
    notifyListeners();

    try {
      _recordingPath = await _audioCaptureService.startRecording();
      _recordingStartedAt = DateTime.now();
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        secondsRemaining -= 1;
        notifyListeners();
        if (secondsRemaining <= 0) {
          timer.cancel();
          await _finishRecordingAndRecognize();
        }
      });
    } catch (error) {
      _setError('Unable to start recording: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> retry() async {
    _recordingTimer?.cancel();
    appState = AppState.idle;
    secondsRemaining = AppConfig.recordingSeconds;
    errorMessage = '';
    recognitionResult = null;
    selectedSuggestion = null;
    spotifyActionResult = null;
    notifyListeners();
  }

  Future<void> confirmPrimarySuggestion() async {
    final suggestion = primarySuggestion;
    if (suggestion == null) {
      _setError('There is no suggested song to confirm.');
      return;
    }
    await chooseSuggestion(suggestion);
  }

  Future<void> chooseSuggestion(SongSuggestion suggestion) async {
    selectedSuggestion = suggestion;
    appState = AppState.processing;
    spotifyActionResult = null;
    notifyListeners();

    await _performSpotifyAdd(suggestion.song, suggestion.artist);
    appState = AppState.success;
    notifyListeners();
  }

  Future<void> _finishRecordingAndRecognize() async {
    final filePath = _recordingPath;
    if (filePath == null) {
      _setError('Recording file is missing. Please try again.');
      return;
    }

    await _audioCaptureService.stopRecording();
    appState = AppState.processing;
    notifyListeners();

    final recordingTimeMs = DateTime.now().difference(_recordingStartedAt ?? DateTime.now()).inMilliseconds;

    try {
      final result = await _backendService.recognize(
        audioPath: filePath,
        recordingTimeMs: recordingTimeMs,
      );
      recognitionResult = result;
      selectedSuggestion = result.primarySuggestion;

      if (result.isSuccessful && result.decision == 'AUTO_ADD') {
        await _performSpotifyAdd(result.song ?? '', result.artist);
        appState = AppState.success;
      } else if (result.needsConfirmation || result.suggestions.isNotEmpty) {
        appState = AppState.lowConfidence;
      } else {
        _setError(result.message ?? 'No confident match was found. Try recording again.');
      }
    } on TimeoutException {
      _setError('The backend did not respond in time. Please retry.');
    } catch (error) {
      _setError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      await _audioCaptureService.deleteRecording(filePath);
      _recordingPath = null;
    }
  }

  Future<void> _performSpotifyAdd(String songName, String? artist) async {
    if (songName.isEmpty) {
      spotifyActionResult = SpotifyActionResult.failure('No recognized song was available for Spotify.');
      return;
    }

    try {
      final accessToken = await _spotifyAuthService.getValidAccessToken();
      spotifyActionResult = await _spotifyPlaylistService.addSongToPlaylist(
        accessToken: accessToken,
        songName: songName,
        artist: artist,
      );
    } catch (error) {
      spotifyActionResult = SpotifyActionResult.failure(
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void _setError(String message) {
    errorMessage = message;
    appState = AppState.error;
    notifyListeners();
  }

  void _clearTransientState() {
    errorMessage = '';
    recognitionResult = null;
    selectedSuggestion = null;
    spotifyActionResult = null;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _backendService.dispose();
    _spotifyAuthService.dispose();
    _spotifyPlaylistService.dispose();
    _audioCaptureService.dispose();
    super.dispose();
  }
}
