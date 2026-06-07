import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ErrorLogEntry {
  final String timestampIso;
  final String source;
  final String message;
  final String stackTrace;

  const ErrorLogEntry({
    required this.timestampIso,
    required this.source,
    required this.message,
    required this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestampIso': timestampIso,
        'source': source,
        'message': message,
        'stackTrace': stackTrace,
      };

  static ErrorLogEntry fromJson(Map<String, dynamic> json) {
    return ErrorLogEntry(
      timestampIso: json['timestampIso']?.toString() ?? '',
      source: json['source']?.toString() ?? 'unknown',
      message: json['message']?.toString() ?? '',
      stackTrace: json['stackTrace']?.toString() ?? '',
    );
  }
}

class ErrorLogger {
  static const String _storageKey = 'argonapp_error_logs_v1';
  static const int _maxEntries = 120;
  static final List<ErrorLogEntry> _entries = [];
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          _entries
            ..clear()
            ..addAll(data.whereType<Map>().map((e) => ErrorLogEntry.fromJson(Map<String, dynamic>.from(e))));
        }
      } catch (_) {
        // Ignore corrupt cache and start clean.
      }
    }
    _initialized = true;
  }

  static List<ErrorLogEntry> get entries => List.unmodifiable(_entries.reversed);

  static Future<void> log({
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    await init();
    _entries.add(
      ErrorLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        source: source,
        message: error.toString(),
        stackTrace: stackTrace?.toString() ?? '',
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    await _persist();
  }

  static Future<void> addCustomNote(String note) async {
    await init();
    _entries.add(
      ErrorLogEntry(
        timestampIso: DateTime.now().toIso8601String(),
        source: 'custom-note',
        message: note,
        stackTrace: '',
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    await _persist();
  }

  static Future<void> clear() async {
    await init();
    _entries.clear();
    await _persist();
  }

  static String buildWhatsappReport() {
    if (_entries.isEmpty) {
      return 'ArgonAPP - Diagnostico\nSin errores capturados.';
    }
    final buffer = StringBuffer();
    buffer.writeln('ArgonAPP - Reporte de errores');
    buffer.writeln('Cantidad: ${_entries.length}');
    buffer.writeln('---');

    for (final entry in _entries.reversed.take(20)) {
      buffer.writeln('[${entry.timestampIso}] ${entry.source}');
      buffer.writeln(entry.message);
      if (entry.stackTrace.isNotEmpty) {
        final shortStack = entry.stackTrace.split('\n').take(4).join('\n');
        buffer.writeln(shortStack);
      }
      buffer.writeln('---');
    }
    return buffer.toString();
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _entries.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(payload));
  }
}

Future<void> captureAndLogError({
  required String source,
  required Object error,
  StackTrace? stackTrace,
}) async {
  await ErrorLogger.log(source: source, error: error, stackTrace: stackTrace);
  debugPrint('[$source] $error');
}
