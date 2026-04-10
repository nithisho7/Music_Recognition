import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../models/spotify_action_result.dart';

class SpotifyPlaylistService {
  SpotifyPlaylistService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _cachedPlaylistIdKey = 'spotify_playlist_id';

  Future<SpotifyActionResult> addSongToPlaylist({
    required String accessToken,
    required String songName,
    String? artist,
  }) async {
    try {
      final userId = await _getCurrentUserId(accessToken);
      final playlistId = await _getOrCreatePlaylist(accessToken, userId);
      final trackUri = await _findTrackUri(accessToken, songName, artist);
      if (trackUri == null) {
        return SpotifyActionResult.failure('Spotify could not find the track.');
      }

      final response = await _client.post(
        Uri.parse('https://api.spotify.com/v1/playlists/$playlistId/tracks'),
        headers: _headers(accessToken),
        body: jsonEncode({'uris': [trackUri]}),
      );

      if (response.statusCode >= 400) {
        return SpotifyActionResult.failure('Spotify add failed: ${response.body}');
      }

      return SpotifyActionResult.success('Added to Spotify playlist successfully.');
    } catch (error) {
      return SpotifyActionResult.failure(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<String> _getCurrentUserId(String accessToken) async {
    final response = await _client.get(
      Uri.parse('https://api.spotify.com/v1/me'),
      headers: _headers(accessToken),
    );
    if (response.statusCode >= 400) {
      throw Exception('Unable to load Spotify profile: ${response.body}');
    }
    final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  Future<String> _getOrCreatePlaylist(String accessToken, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedId = prefs.getString(_cachedPlaylistIdKey);
    if (cachedId != null && cachedId.isNotEmpty) {
      return cachedId;
    }

    final playlistsResponse = await _client.get(
      Uri.https('api.spotify.com', '/v1/me/playlists', {'limit': '50'}),
      headers: _headers(accessToken),
    );
    if (playlistsResponse.statusCode >= 400) {
      throw Exception('Unable to list Spotify playlists: ${playlistsResponse.body}');
    }

    final Map<String, dynamic> playlistsJson = jsonDecode(playlistsResponse.body) as Map<String, dynamic>;
    final items = (playlistsJson['items'] as List<dynamic>? ?? const <dynamic>[]).whereType<Map<String, dynamic>>();
    for (final item in items) {
      if ((item['name'] as String?) == AppConfig.spotifyPlaylistName) {
        final playlistId = item['id'] as String;
        await prefs.setString(_cachedPlaylistIdKey, playlistId);
        return playlistId;
      }
    }

    final createResponse = await _client.post(
      Uri.parse('https://api.spotify.com/v1/users/$userId/playlists'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'name': AppConfig.spotifyPlaylistName,
        'description': 'Songs identified by the Music Recognition and Automation System.',
        'public': false,
      }),
    );

    if (createResponse.statusCode >= 400) {
      throw Exception('Unable to create Spotify playlist: ${createResponse.body}');
    }

    final Map<String, dynamic> createJson = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final playlistId = createJson['id'] as String;
    await prefs.setString(_cachedPlaylistIdKey, playlistId);
    return playlistId;
  }

  Future<String?> _findTrackUri(String accessToken, String songName, String? artist) async {
    final query = artist == null || artist.isEmpty ? songName : 'track:$songName artist:$artist';
    final response = await _client.get(
      Uri.https('api.spotify.com', '/v1/search', {
        'q': query,
        'type': 'track',
        'limit': '1',
      }),
      headers: _headers(accessToken),
    );

    if (response.statusCode >= 400) {
      throw Exception('Spotify track search failed: ${response.body}');
    }

    final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
    final tracks = json['tracks'] as Map<String, dynamic>?;
    final items = (tracks?['items'] as List<dynamic>? ?? const <dynamic>[]).whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) {
      return null;
    }
    return items.first['uri'] as String?;
  }

  Map<String, String> _headers(String accessToken) {
    return {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
  }

  void dispose() {
    _client.close();
  }
}
