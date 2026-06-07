import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'watch_party_service.dart';

class RemoteControlService {
  final String endpoint;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _connected = false;
  String? _pairingCode;
  bool _paired = false;

  final StreamController<String> _pairingCodeController = StreamController<String>.broadcast();
  final StreamController<bool> _pairingStatusController = StreamController<bool>.broadcast();
  final StreamController<String> _remoteSearchController = StreamController<String>.broadcast();

  RemoteControlService({String? endpoint})
      : endpoint = endpoint ?? WatchPartyService.defaultEndpoint;

  bool get isConnected => _connected;
  bool get isPaired => _paired;
  String? get pairingCode => _pairingCode;

  Stream<String> get pairingCodeStream => _pairingCodeController.stream;
  Stream<bool> get pairingStatusStream => _pairingStatusController.stream;
  Stream<String> get remoteSearchStream => _remoteSearchController.stream;

  Future<void> connect() async {
    if (_connected) return;

    final candidates = <String>[
      endpoint,
      ...WatchPartyService.fallbackEndpoints.where((value) => value != endpoint),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final uri = Uri.parse(candidate);
        _channel = WebSocketChannel.connect(uri);
        _connected = true;

        _sub = _channel!.stream.listen(
          _onData,
          onError: (err) => _onClosed(),
          onDone: () => _onClosed(),
          cancelOnError: false,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No se pudo conectar al servidor de control remoto');
  }

  void _onClosed() {
    _connected = false;
    _paired = false;
    _pairingCode = null;
    _pairingStatusController.add(false);
  }

  // TV Side: Request pairing code
  void registerTv() {
    if (!_connected) return;
    _sendRaw({
      'type': 'register_tv',
      'payload': {},
    });
  }

  // Phone Side: Pair with TV code
  void pairPhone(String code) {
    if (!_connected) return;
    _sendRaw({
      'type': 'pair_phone',
      'payload': {'code': code},
    });
  }

  // Phone Side: Send remote keypress
  void sendKey(String key) {
    if (!_connected || !_paired) return;
    _sendRaw({
      'type': 'remote_key',
      'payload': {'key': key},
    });
  }

  // Phone Side: Send remote search text query
  void sendSearch(String query) {
    if (!_connected || !_paired) return;
    _sendRaw({
      'type': 'remote_search',
      'payload': {'query': query},
    });
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;

      final type = decoded['type']?.toString() ?? '';
      final payload = Map<String, dynamic>.from(decoded['payload'] ?? {});

      if (type == 'tv_registered') {
        _pairingCode = payload['code']?.toString();
        if (_pairingCode != null) {
          _pairingCodeController.add(_pairingCode!);
        }
      } else if (type == 'phone_paired' || type == 'paired_to_tv') {
        _paired = true;
        _pairingStatusController.add(true);
      } else if (type == 'tv_disconnected' || type == 'phone_disconnected') {
        _paired = false;
        _pairingStatusController.add(false);
      } else if (type == 'remote_key') {
        final key = payload['key']?.toString() ?? '';
        _simulateKey(key);
      } else if (type == 'remote_search') {
        final query = payload['query']?.toString() ?? '';
        _remoteSearchController.add(query);
      }
    } catch (_) {}
  }

  // Simulates keyboard presses based on TV remote D-Pad controls
  void _simulateKey(String key) {
    LogicalKeyboardKey? logicalKey;
    PhysicalKeyboardKey? physicalKey;
    switch (key) {
      case 'ArrowUp':
        logicalKey = LogicalKeyboardKey.arrowUp;
        physicalKey = PhysicalKeyboardKey.arrowUp;
        break;
      case 'ArrowDown':
        logicalKey = LogicalKeyboardKey.arrowDown;
        physicalKey = PhysicalKeyboardKey.arrowDown;
        break;
      case 'ArrowLeft':
        logicalKey = LogicalKeyboardKey.arrowLeft;
        physicalKey = PhysicalKeyboardKey.arrowLeft;
        break;
      case 'ArrowRight':
        logicalKey = LogicalKeyboardKey.arrowRight;
        physicalKey = PhysicalKeyboardKey.arrowRight;
        break;
      case 'Enter':
        logicalKey = LogicalKeyboardKey.enter;
        physicalKey = PhysicalKeyboardKey.enter;
        break;
      case 'Backspace':
        logicalKey = LogicalKeyboardKey.backspace;
        physicalKey = PhysicalKeyboardKey.backspace;
        break;
    }

    if (logicalKey != null && physicalKey != null) {
      try {
        final timeStamp = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
        HardwareKeyboard.instance.handleKeyEvent(
          KeyDownEvent(
            physicalKey: physicalKey,
            logicalKey: logicalKey,
            timeStamp: timeStamp,
          ),
        );
        HardwareKeyboard.instance.handleKeyEvent(
          KeyUpEvent(
            physicalKey: physicalKey,
            logicalKey: logicalKey,
            timeStamp: timeStamp,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _pairingCodeController.close();
    await _pairingStatusController.close();
    await _remoteSearchController.close();
  }

  Timer? _reconnectTimer;
}
