import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

class SpotifyAuthService {
  SpotifyAuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _tokenKey = 'spotify_access_token';
  static const String _refreshKey = 'spotify_refresh_token';
  static const String _expiryKey = 'spotify_expiry_epoch_ms';

  Future<String> getValidAccessToken() async {
    final session = await _loadSession();
    if (session != null && !session.isExpired) {
      return session.accessToken;
    }
    if (session != null && session.refreshToken != null && session.refreshToken!.isNotEmpty) {
      final refreshed = await _refresh(session.refreshToken!);
      await _persistSession(refreshed);
      return refreshed.accessToken;
    }
    final authorized = await _authorizeWithPkce();
    await _persistSession(authorized);
    return authorized.accessToken;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_expiryKey);
  }

  Future<_SpotifySession?> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_tokenKey);
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return _SpotifySession(
      accessToken: accessToken,
      refreshToken: prefs.getString(_refreshKey),
      expiresAtEpochMs: prefs.getInt(_expiryKey) ?? 0,
    );
  }

  Future<void> _persistSession(_SpotifySession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.accessToken);
    if (session.refreshToken != null) {
      await prefs.setString(_refreshKey, session.refreshToken!);
    }
    await prefs.setInt(_expiryKey, session.expiresAtEpochMs);
  }

  Future<_SpotifySession> _authorizeWithPkce() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);
    final authUri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': AppConfig.spotifyClientId,
      'response_type': 'code',
      'redirect_uri': AppConfig.spotifyRedirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'scope': 'playlist-modify-public playlist-modify-private user-read-private',
      'show_dialog': 'false',
    });

    final callback = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: Uri.parse(AppConfig.spotifyRedirectUri).scheme,
    );
    final code = Uri.parse(callback).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('Spotify login did not return an authorization code.');
    }

    final tokenResponse = await _client.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': AppConfig.spotifyClientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': AppConfig.spotifyRedirectUri,
        'code_verifier': verifier,
      },
    );

    if (tokenResponse.statusCode >= 400) {
      throw Exception('Spotify token exchange failed: ${tokenResponse.body}');
    }

    final Map<String, dynamic> json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    return _SpotifySession.fromJson(json);
  }

  Future<_SpotifySession> _refresh(String refreshToken) async {
    final response = await _client.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': AppConfig.spotifyClientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode >= 400) {
      throw Exception('Spotify token refresh failed: ${response.body}');
    }

    final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
    return _SpotifySession.fromJson(json, fallbackRefreshToken: refreshToken);
  }

  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  void dispose() {
    _client.close();
  }
}

class _SpotifySession {
  const _SpotifySession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtEpochMs,
  });

  final String accessToken;
  final String? refreshToken;
  final int expiresAtEpochMs;

  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= expiresAtEpochMs - 60000;
  }

  factory _SpotifySession.fromJson(Map<String, dynamic> json, {String? fallbackRefreshToken}) {
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return _SpotifySession(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? fallbackRefreshToken,
      expiresAtEpochMs: DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000),
    );
  }
}
