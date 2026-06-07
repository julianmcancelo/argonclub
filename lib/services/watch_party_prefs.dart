import 'package:shared_preferences/shared_preferences.dart';

class WatchPartyPrefs {
  static const String _nameKey = 'argon_watch_party_name';

  static Future<String> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_nameKey)?.trim() ?? '';
    return value.isEmpty ? 'Invitado' : value;
  }

  static Future<void> setDisplayName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().isEmpty ? 'Invitado' : value.trim();
    await prefs.setString(_nameKey, normalized);
  }
}
