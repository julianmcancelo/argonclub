import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryService {
  static const String _storageKey = 'argon_watch_history_v1';
  static const int _maxEntries = 80;

  static Future<void> saveProgress({
    required String playbackKey,
    required String mediaType,
    required String mediaId,
    required String title,
    required String posterUrl,
    required int positionSeconds,
    required int durationSeconds,
    String videoUrl = '',
    Map<String, String> headers = const {},
    List<Map<String, dynamic>> serverQueue = const [],
    bool completed = false,
  }) async {
    final key = playbackKey.trim();
    if (key.isEmpty) return;
    if (durationSeconds <= 0) return;

    final safeDuration = durationSeconds < 1 ? 1 : durationSeconds;
    final safePosition = positionSeconds.clamp(0, safeDuration);
    final progress = (safePosition / safeDuration).clamp(0.0, 1.0);

    final list = await _readEntries();
    list.removeWhere((e) => (e['playback_key']?.toString() ?? '') == key);

    final shouldRemove = completed || progress >= 0.97 || safePosition <= 5;
    if (shouldRemove) {
      await _writeEntries(list);
      return;
    }

    final entry = <String, dynamic>{
      'playback_key': key,
      'media_type': mediaType.trim(),
      'media_id': mediaId.trim(),
      'title': title.trim(),
      'poster_url': posterUrl.trim(),
      'position_seconds': safePosition,
      'duration_seconds': safeDuration,
      'progress': progress,
      'video_url': videoUrl.trim(),
      'headers': Map<String, String>.from(headers),
      'server_queue': serverQueue.map((s) {
        final headersMap = <String, String>{};
        final rawHeaders = s['headers'];
        if (rawHeaders is Map) {
          rawHeaders.forEach((k, v) {
            if (k != null && v != null) headersMap[k.toString()] = v.toString();
          });
        }
        return <String, dynamic>{
          'name': (s['name'] ?? 'SERVIDOR').toString(),
          'url': (s['url'] ?? '').toString(),
          'serverType': (s['serverType'] ?? '').toString(),
          'headers': headersMap,
        };
      }).where((s) => (s['url'] as String).isNotEmpty).toList(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    list.insert(0, entry);
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }
    await _writeEntries(list);
  }

  static Future<List<Map<String, dynamic>>> getContinueWatching({int limit = 12}) async {
    final list = await _readEntries();
    list.sort((a, b) => (b['updated_at'] as int? ?? 0).compareTo(a['updated_at'] as int? ?? 0));
    final filtered = list.where((e) {
      final position = (e['position_seconds'] as num?)?.toInt() ?? 0;
      final duration = (e['duration_seconds'] as num?)?.toInt() ?? 0;
      final progress = (e['progress'] as num?)?.toDouble() ?? 0.0;
      return duration > 0 && position > 5 && progress > 0.01 && progress < 0.97;
    }).toList();

    final cap = filtered.isEmpty ? 0 : limit.clamp(1, filtered.length);
    return filtered.take(cap).toList();
  }

  static Future<int?> getResumeSeconds(String playbackKey) async {
    final key = playbackKey.trim();
    if (key.isEmpty) return null;
    final list = await _readEntries();
    for (final e in list) {
      if ((e['playback_key']?.toString() ?? '') == key) {
        return (e['position_seconds'] as num?)?.toInt();
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _readEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _writeEntries(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(entries));
  }
}
