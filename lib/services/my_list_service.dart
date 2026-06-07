import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MyListService {
  static const String _prefix = 'argon_my_list_v1_';
  static const int _maxItems = 160;

  static Future<List<Map<String, dynamic>>> getItems(String profileId) async {
    final id = profileId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$id');
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final out = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      out.sort((a, b) => (b['added_at'] as int? ?? 0).compareTo((a['added_at'] as int? ?? 0)));
      return out;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<bool> contains({
    required String profileId,
    required String mediaType,
    required String mediaId,
  }) async {
    final key = _itemKey(mediaType, mediaId);
    if (key.isEmpty) return false;
    final items = await getItems(profileId);
    return items.any((e) => (e['item_key']?.toString() ?? '') == key);
  }

  static Future<bool> toggleItem({
    required String profileId,
    required Map<String, dynamic> itemData,
    required String mediaType,
    required String mediaId,
  }) async {
    final key = _itemKey(mediaType, mediaId);
    if (key.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final items = await getItems(profileId);
    final idx = items.indexWhere((e) => (e['item_key']?.toString() ?? '') == key);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (idx >= 0) {
      items.removeAt(idx);
      await prefs.setString('$_prefix${profileId.trim()}', jsonEncode(items));
      return false;
    }

    final entry = <String, dynamic>{
      'item_key': key,
      'media_type': mediaType,
      'media_id': mediaId,
      'title': (itemData['title'] ?? itemData['tv_name'] ?? 'Contenido').toString(),
      'poster_url': (itemData['tmdb_poster_url'] ??
              itemData['poster_url'] ??
              itemData['thumbnail_url'] ??
              itemData['image_url'] ??
              '')
          .toString(),
      'description': (itemData['description'] ?? '').toString(),
      'genre': (itemData['genre'] ?? '').toString(),
      'year': (itemData['year'] ?? itemData['release_year'] ?? '').toString(),
      'added_at': now,
    };

    items.insert(0, entry);
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    await prefs.setString('$_prefix${profileId.trim()}', jsonEncode(items));
    return true;
  }

  static String _itemKey(String mediaType, String mediaId) {
    final mt = mediaType.trim().toLowerCase();
    final id = mediaId.trim();
    if (id.isEmpty) return '';
    return '$mt::$id';
  }
}
