import 'package:shared_preferences/shared_preferences.dart';

class ServerMemory {
  static const String _prefix = 'argon_last_ok_server_v1::';

  static Future<void> saveLastWorkingServer({
    required String playbackKey,
    required String serverUrl,
    required String serverName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$playbackKey',
      '$serverName|||$serverUrl',
    );
  }

  static Future<String?> getLastWorkingServerUrl(String playbackKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$playbackKey');
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|||');
    if (parts.length < 2) return null;
    final url = parts[1].trim();
    return url.isEmpty ? null : url;
  }
}
