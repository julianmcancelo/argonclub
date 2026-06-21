import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/splash_screen.dart';
import 'screens/search_screen.dart';
import 'theme/argon_theme.dart';
import 'services/error_logger.dart';
import 'services/remote_control_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      40 * 1024 * 1024; // 40 MB max
  PaintingBinding.instance.imageCache.maximumSize = 60; // 60 images max
  await initializeDateFormatting('es', null);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await ErrorLogger.init();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    captureAndLogError(
      source: 'flutter.framework',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    captureAndLogError(
      source: 'platform.dispatcher',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ArgonAPP',
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const DirectionalFocusIntent(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const DirectionalFocusIntent(TraversalDirection.down),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DirectionalFocusIntent(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const DirectionalFocusIntent(TraversalDirection.right),
      },
      theme: ArgonTheme.darkTheme().copyWith(
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
      ),
      builder: (context, child) => RemoteControlBridge(
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const SplashScreen(),
    );
  }
}

class RemoteControlBridge extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const RemoteControlBridge({
    Key? key,
    required this.navigatorKey,
    required this.child,
  }) : super(key: key);

  @override
  State<RemoteControlBridge> createState() => _RemoteControlBridgeState();
}

class _RemoteControlBridgeState extends State<RemoteControlBridge> {
  final RemoteControlService _service = RemoteControlService();
  StreamSubscription<String>? _keySub;
  StreamSubscription<String>? _searchSub;
  StreamSubscription<String>? _codeSub;
  StreamSubscription<String>? _deviceSub;
  StreamSubscription<bool>? _statusSub;
  bool _paired = false;
  String? _code;
  String _device = 'Argon Remote';
  String? _lastCommand;

  @override
  void initState() {
    super.initState();
    _keySub = _service.remoteKeyStream.listen(_handleRemoteKey);
    _searchSub = _service.remoteSearchStream.listen(_handleRemoteSearch);
    _codeSub = _service.pairingCodeStream.listen((code) {
      if (mounted) setState(() => _code = code);
    });
    _deviceSub = _service.pairedDeviceStream.listen((device) {
      if (mounted) setState(() => _device = device);
    });
    _statusSub = _service.pairingStatusStream.listen((paired) {
      if (mounted) setState(() => _paired = paired);
    });
    _startRemoteReceiver();
  }

  Future<void> _startRemoteReceiver() async {
    try {
      await _service.connect();
      _service.registerTv();
    } catch (_) {}
  }

  void _handleRemoteSearch(String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;
    widget.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(remoteQuery: normalizedQuery),
      ),
    );
  }

  void _handleRemoteKey(String key) {
    if (mounted) setState(() => _lastCommand = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final mapping = _keyMapping(key);
      if (mapping == null) return;
      var primaryFocus = FocusManager.instance.primaryFocus;
      final hadNoFocus =
          primaryFocus == null ||
          primaryFocus == FocusManager.instance.rootScope;
      if (hadNoFocus) {
        FocusManager.instance.rootScope.nextFocus();
        if (key.startsWith('Arrow')) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _moveFocus(key));
          return;
        }
      }
      primaryFocus = FocusManager.instance.primaryFocus;
      switch (key) {
        case 'ArrowUp':
        case 'ArrowDown':
        case 'ArrowLeft':
        case 'ArrowRight':
          _moveFocus(key);
          return;
      }

      final (logicalKey, physicalKey) = mapping;
      final event = KeyDownEvent(
        physicalKey: physicalKey,
        logicalKey: logicalKey,
        timeStamp: Duration.zero,
      );

      var node = FocusManager.instance.primaryFocus;
      var handled = false;
      while (node != null && !handled) {
        final callback = node.onKeyEvent;
        if (callback != null) {
          handled = callback(node, event) == KeyEventResult.handled;
        }
        node = node.parent;
      }
      if (handled) return;

      switch (key) {
        case 'Enter':
          final focusContext = primaryFocus?.context;
          if (focusContext != null) {
            Actions.maybeInvoke(focusContext, const ActivateIntent());
          }
          break;
        case 'Escape':
        case 'Backspace':
          widget.navigatorKey.currentState?.maybePop();
          break;
      }
    });
  }

  void _moveFocus(String key) {
    final focusTarget =
        FocusManager.instance.primaryFocus ?? FocusManager.instance.rootScope;
    switch (key) {
      case 'ArrowUp':
        if (!focusTarget.focusInDirection(TraversalDirection.up)) {
          focusTarget.previousFocus();
        }
        break;
      case 'ArrowDown':
        if (!focusTarget.focusInDirection(TraversalDirection.down)) {
          focusTarget.nextFocus();
        }
        break;
      case 'ArrowLeft':
        if (!focusTarget.focusInDirection(TraversalDirection.left)) {
          focusTarget.previousFocus();
        }
        break;
      case 'ArrowRight':
        if (!focusTarget.focusInDirection(TraversalDirection.right)) {
          focusTarget.nextFocus();
        }
        break;
    }
  }

  (LogicalKeyboardKey, PhysicalKeyboardKey)? _keyMapping(String key) {
    switch (key) {
      case 'ArrowUp':
        return (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp);
      case 'ArrowDown':
        return (LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown);
      case 'ArrowLeft':
        return (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft);
      case 'ArrowRight':
        return (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight);
      case 'Enter':
        return (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
      case 'Escape':
        return (LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape);
      case 'Backspace':
        return (LogicalKeyboardKey.backspace, PhysicalKeyboardKey.backspace);
      case 'MediaPlayPause':
        return (
          LogicalKeyboardKey.mediaPlayPause,
          PhysicalKeyboardKey.mediaPlayPause,
        );
      case 'MediaRewind':
        return (
          LogicalKeyboardKey.mediaRewind,
          PhysicalKeyboardKey.mediaRewind,
        );
      case 'MediaFastForward':
        return (
          LogicalKeyboardKey.mediaFastForward,
          PhysicalKeyboardKey.mediaFastForward,
        );
    }
    return null;
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _searchSub?.cancel();
    _codeSub?.cancel();
    _deviceSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_paired || _code != null)
          Positioned(
            bottom: 18,
            right: 16,
            child: SafeArea(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (_paired ? Colors.green : Colors.orange).withOpacity(
                      0.22,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          (_paired ? Colors.greenAccent : Colors.orangeAccent)
                              .withOpacity(0.7),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 16),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _paired
                              ? Icons.phonelink_ring_rounded
                              : Icons.settings_remote_rounded,
                          size: 17,
                          color: _paired
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _paired
                              ? 'Conectado: $_device${_lastCommand == null ? '' : ' · ${_commandLabel(_lastCommand!)}'}'
                              : 'Vincular control · PIN ${_code ?? '...'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _commandLabel(String key) {
    switch (key) {
      case 'ArrowUp':
        return '↑';
      case 'ArrowDown':
        return '↓';
      case 'ArrowLeft':
        return '←';
      case 'ArrowRight':
        return '→';
      case 'Enter':
        return 'OK';
      case 'Escape':
      case 'Backspace':
        return 'Atrás';
      default:
        return key;
    }
  }
}
