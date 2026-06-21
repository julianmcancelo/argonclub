import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';

class WatchPartySession {
  final String roomId;
  final String peerName;
  final bool isHost;

  const WatchPartySession({
    required this.roomId,
    required this.peerName,
    required this.isHost,
  });

  String get normalizedRoomId => roomId.trim().toUpperCase();
}

class WatchPartyEvent {
  final String type;
  final Map<String, dynamic> payload;
  final int timestamp;

  const WatchPartyEvent({
    required this.type,
    required this.payload,
    required this.timestamp,
  });
}

class WatchPartyService {
  static const String _envEndpoint = String.fromEnvironment('WATCH_PARTY_WS_URL');
  static const String _productionEndpoint = 'wss://argonapp.onrender.com';
  static const String _emulatorEndpoint = 'ws://10.0.2.2:3000';
  // Default backend endpoint - prefer deployed Render backend
  static final String defaultEndpoint =
      _envEndpoint.isNotEmpty ? _envEndpoint : _productionEndpoint;
  static const List<String> fallbackEndpoints = <String>[
    _productionEndpoint,
    _emulatorEndpoint,
  ];

  final String endpoint;
  final String roomId;
  final String peerId;
  final String peerName;
  final bool isHost;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final StreamController<WatchPartyEvent> _events = StreamController<WatchPartyEvent>.broadcast();

  bool _connected = false;
  bool _joined = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Completer<void>? _joinCompleter;

  WatchPartyService({
    required this.roomId,
    required this.peerId,
    required this.peerName,
    this.isHost = false,
    String? endpoint,
  }) : endpoint = endpoint ?? defaultEndpoint;

  bool get isConnected => _connected && _joined;
  Stream<WatchPartyEvent> get events => _events.stream;

  Future<void> connect() async {
    if (_connected) return;

    try {
      _connected = false;
      _joined = false;
      _reconnectAttempts = 0;
      _joinCompleter = Completer<void>();
      await _attemptConnectWithFallbacks();
      await _joinCompleter!.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('La sala no respondio a tiempo'),
      );
    } catch (e) {
      _emitError('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> _attemptConnectWithFallbacks() async {
    final candidates = <String>[
      endpoint,
      ...fallbackEndpoints.where((value) => value != endpoint),
    ];
    Object? lastError;
    for (final candidate in candidates) {
      try {
        await _warmupEndpointIfNeeded(candidate);
        await _attemptConnect(candidate);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No se pudo conectar a ningun backend de Watch Party');
  }

  Future<void> _warmupEndpointIfNeeded(String targetEndpoint) async {
    if (kIsWeb) return;
    final uri = Uri.tryParse(targetEndpoint);
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    if (!host.contains('onrender.com')) return;

    final healthUri = uri.replace(
      scheme: uri.scheme == 'wss' ? 'https' : 'http',
      path: '/health',
      query: null,
    );

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(healthUri);
      final response = await request.close().timeout(const Duration(seconds: 25));
      await response.drain<void>();
      client.close(force: true);
    } catch (_) {
      // Non-blocking warmup. WebSocket connect still attempts after this.
    }
  }

  Future<void> _attemptConnect(String targetEndpoint) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(targetEndpoint));
      _channel = channel;
      _connected = true;
      _reconnectAttempts = 0;

      _sub = channel.stream.listen(
        _onData,
        onError: (error) {
          _onConnectionError(error);
        },
        onDone: () {
          _onConnectionClosed();
        },
        cancelOnError: false,
      );

      // Send join message
      _sendRaw({
        'type': 'join',
        'payload': {
          'room': roomId.toUpperCase().trim(),
          'peer': peerId,
          'name': peerName,
          'host': isHost,
        },
      });

      _startHeartbeat();
    } catch (e) {
      _connected = false;
      _emitError('Connection error on $targetEndpoint: $e');
      _scheduleReconnect();
      rethrow;
    }
  }

  void _onConnectionError(dynamic error) {
    _connected = false;
    _joined = false;
    _stopHeartbeat();
    if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
      _joinCompleter!.completeError(error);
    }
    _emitError('Connection error: $error');
    _scheduleReconnect();
  }

  void _onConnectionClosed() {
    _connected = false;
    _joined = false;
    _stopHeartbeat();
    if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
      _joinCompleter!.completeError(StateError('Server closed connection before join'));
    }
    _emitEvent(WatchPartyEvent(
      type: 'closed',
      payload: {'reason': 'Server closed connection'},
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _emitError('Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delaySeconds = math.min(math.pow(2, _reconnectAttempts).toInt(), 30);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_connected) {
        _attemptConnectWithFallbacks();
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_connected) {
        sendPing();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void sendSync({
    required String action,
    required int positionMs,
    required bool isPlaying,
  }) {
    if (!isHost || !_connected) return;
    _sendRaw({
      'type': 'sync',
      'payload': {
        'action': action,
        'positionMs': positionMs,
        'isPlaying': isPlaying,
      },
    });
  }

  void setMedia({required String mediaKey, required String currentUrl}) {
    if (!isHost || !_connected) return;
    _sendRaw({
      'type': 'set_media',
      'payload': {
        'mediaKey': mediaKey,
        'currentUrl': currentUrl,
      },
    });
  }

  void sendPing() {
    if (!_connected) return;
    _sendRaw({'type': 'ping'});
  }

  void setReady(bool ready) {
    if (!_connected) return;
    _sendRaw({
      'type': 'set_ready',
      'payload': {'ready': ready},
    });
  }

  void sendChatMessage(String text) {
    if (!_connected) return;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    _sendRaw({
      'type': 'chat_message',
      'payload': {'text': normalized},
    });
  }

  void startPlayback() {
    if (!_connected || !isHost) return;
    _sendRaw({'type': 'start_playback', 'payload': {}});
  }

  void _sendRaw(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (e) {
      _emitError('Failed to send message: $e');
    }
  }

  void _onData(dynamic raw) {
    try {
      final text = raw?.toString() ?? '';
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);

      final type = data['type']?.toString() ?? '';
      final timestamp = (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

      if (type == 'welcome') {
        _joined = true;
        if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
          _joinCompleter!.complete();
        }
        final payload = Map<String, dynamic>.from(data['payload'] ?? {});
        _emitEvent(WatchPartyEvent(
          type: 'welcome',
          payload: payload,
          timestamp: timestamp,
        ));
        return;
      }

      if (type == 'error') {
        if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
          _joinCompleter!.completeError(
            StateError(data['payload']?['message']?.toString() ?? 'Unknown error'),
          );
        }
        _emitError(data['payload']?['message'] ?? 'Unknown error');
        return;
      }

      if (type == 'pong') {
        // Ignore pong responses
        return;
      }

      // Broadcast messages
      if (['roster_updated', 'media_changed', 'sync', 'host_changed', 'room_state', 'chat_message', 'playback_started'].contains(type)) {
        final payload = Map<String, dynamic>.from(data['payload'] ?? {});
        _emitEvent(WatchPartyEvent(
          type: type,
          payload: payload,
          timestamp: timestamp,
        ));
        return;
      }
    } catch (e) {
      _emitError('Payload parse error: $e');
    }
  }

  void _emitEvent(WatchPartyEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  void _emitError(String message) {
    _emitEvent(WatchPartyEvent(
      type: 'error',
      payload: {'message': message},
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> close() async {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _connected = false;
    _joined = false;
    _joinCompleter = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }
}
