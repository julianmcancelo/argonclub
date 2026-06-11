import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_windows/webview_windows.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:dio/dio.dart';
import '../services/error_logger.dart';
import '../services/server_memory.dart';
import '../services/watch_history.dart';
import '../services/watch_party_service.dart';
import 'dart:async';
import 'dart:ui';
import '../api/api_client.dart';
import 'details_screen.dart';
import '../widgets/cast_device_dialog.dart';
import '../services/web_helper_stub.dart'
    if (dart.library.html) '../services/web_helper_web.dart' as web_helper;
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final bool isDirect;
  final Map<String, String> headers;
  final List<Map<String, dynamic>> serverQueue;
  final List<dynamic>? episodesList;
  final int? currentEpisodeIndex;
  final String? mediaTitle;
  final String? mediaType;
  final String? mediaId;
  final String? mediaPosterUrl;
  final String playbackKey;
  final int startPositionSeconds;
  final WatchPartySession? initialWatchPartySession;

  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    this.isDirect = false,
    this.headers = const {},
    this.serverQueue = const [],
    this.episodesList,
    this.currentEpisodeIndex,
    this.mediaTitle,
    this.mediaType,
    this.mediaId,
    this.mediaPosterUrl,
    this.playbackKey = '',
    this.startPositionSeconds = 0,
    this.initialWatchPartySession,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  String _accentName = 'Mono';

  Color get currentAccentColor {
    switch (_accentName) {
      case 'Arena':
        return const Color(0xFFF2C078);
      case 'Niebla':
        return const Color(0xFFB7D8EE);
      case 'Mono':
      default:
        return const Color(0xFFFF6B6B);
    }
  }

  Color get colorBrandA => currentAccentColor;
  Color get colorBrandB => _accentName == 'Mono' ? const Color(0xFFF97316) : currentAccentColor;

  Future<void> _loadTweakPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _accentName = prefs.getString('argon_tweak_accent') ?? 'Mono';
        });
      }
    } catch (_) {}
  }

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _showNeutralFallback = false;
  bool _isIframePlayer = false;
  String _iframeViewId = '';
  String _statusMessage = 'Inicializando...';
  bool _resolvedVideo = false;
  final List<String> _candidateQueue = [];
  final Set<String> _triedCandidates = {};
  int _retryCount = 0;
  bool _nativeCompatibilityMode = false;
  int _fallbackTimerToken = 0;
  String _lastErrorType = 'Sin error';
  String _lastErrorDetail = '';

  late final List<Map<String, dynamic>> _serverQueue;
  int _activeServerIndex = 0;
  String _activeVideoUrl = '';
  Map<String, String> _activeHeaders = const {};
  String _activeServerName = 'SERVIDOR';
  String _activeServerType = ''; // 'hls' | 'mp4' | 'custom' | 'embed' | ''
  
  // Windows Webview
  final _webviewWindowsController = WebviewController();
  
  // Flutter Webview (Android/iOS)
  WebViewController? _webviewFlutterController;

  // Autoplay and Recommendations variables
  bool _countdownActive = false;
  int _countdownSeconds = 20;
  Timer? _countdownTimer;
  bool _showNextEpisodeOverlay = false;
  bool _showRecommendations = false;
  List<dynamic> _recommendations = [];
  bool _loadingRecommendations = true;
  bool _isResolvingNextEpisode = false;
  int _lastProgressSavedAtSecond = -1;
  bool _resumeApplied = false;
  WatchPartyService? _partyService;
  StreamSubscription<WatchPartyEvent>? _partySubscription;
  Timer? _partyHeartbeatTimer;
  bool _partyConnecting = false;
  bool _partyIsHost = false;
  String _partyRoomId = '';
  String _partyPeerName = 'Invitado';
  String _partyStatus = 'Sin sala';
  int _partyMembers = 1;
  String _partyPeerId = '';
  bool _partyApplyingRemote = false;
  int _partySuppressBroadcastUntilMs = 0;
  bool? _partyLastPlayingState;
  int _partyLastSentPositionMs = -1;
  int _partyLastHeartbeatMs = 0;
  String _transportOverlayText = '';
  Timer? _transportOverlayTimer;

  @override
  void initState() {
    super.initState();
    _loadTweakPreferences();
    WakelockPlus.enable();
    
    // Hide status bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _serverQueue = _buildServerQueue();
    _setActiveServer(0);
    _startPlaybackForActiveServer();
    _loadRecommendations();
    _partyPeerId = _generatePartyPeerId();
    final initialParty = widget.initialWatchPartySession;
    if (initialParty != null) {
      Future<void>(() async {
        await _joinWatchParty(
          roomId: initialParty.roomId,
          peerName: initialParty.peerName,
          isHost: initialParty.isHost,
        );
      });
    }
  }

  List<Map<String, dynamic>> _buildServerQueue() {
    final out = <Map<String, dynamic>>[];

    Map<String, dynamic> normalize(Map<String, dynamic> raw) {
      final url = raw['url']?.toString() ?? '';
      final name = raw['name']?.toString() ?? 'SERVIDOR';
      final headersRaw = raw['headers'];
      final headers = <String, String>{};
      if (headersRaw is Map) {
        headersRaw.forEach((key, value) {
          if (key != null && value != null) {
            headers[key.toString()] = value.toString();
          }
        });
      }
      // Preserve serverType so playback routing is accurate
      final serverType = raw['serverType']?.toString() ?? '';
      return {
        'name': name,
        'url': url,
        'headers': headers,
        if (serverType.isNotEmpty) 'serverType': serverType,
      };
    }

    if (widget.serverQueue.isNotEmpty) {
      for (final server in widget.serverQueue) {
        final normalized = normalize(server);
        if ((normalized['url'] as String).isNotEmpty) {
          out.add(normalized);
        }
      }
    }

    if (out.isEmpty) {
      out.add({
        'name': 'SERVIDOR 1',
        'url': widget.videoUrl,
        'headers': widget.headers,
      });
    }

    return out;
  }

  void _setActiveServer(int index) {
    final server = _serverQueue[index];
    _activeServerIndex = index;
    _activeServerName = server['name']?.toString() ?? 'SERVIDOR ${index + 1}';
    _activeVideoUrl = server['url']?.toString() ?? '';
    _activeServerType = server['serverType']?.toString() ?? '';
    final headersRaw = server['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      headersRaw.forEach((key, value) {
        if (key != null && value != null) {
          headers[key.toString()] = value.toString();
        }
      });
    }
    _activeHeaders = headers;

    // Notify watch party host about media change
    if (_partyIsHost && _partyService?.isConnected == true) {
      final mediaKey = _currentMediaKeyForParty();
      _partyService?.setMedia(
        mediaKey: mediaKey,
        currentUrl: _activeVideoUrl,
      );
    }
  }

  void _startPlaybackForActiveServer() {
    // Use serverType classification (from DetailsScreen._classifyServerType) when available.
    // This mirrors TvDetailsActivity.Il0() logic:
    //   hls/mp4 → direct ExoPlayer
    //   embed/custom → WebView extraction
    final isDirect = _activeServerType == 'hls' ||
        _activeServerType == 'mp4' ||
        (_activeServerType.isEmpty && _looksLikeStreamUrl(_activeVideoUrl));
    if (isDirect) {
      _initializePlayer(_activeVideoUrl);
    } else {
      _extractAndPlay();
    }
  }

  String _shortUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) {
      return url.length > 70 ? '${url.substring(0, 70)}...' : url;
    }
    final path = parsed.path.length > 42 ? '${parsed.path.substring(0, 42)}...' : parsed.path;
    final query = parsed.query.isEmpty
        ? ''
        : '?${parsed.query.length > 110 ? '${parsed.query.substring(0, 110)}...' : parsed.query}';
    return '${parsed.scheme}://${parsed.host}$path$query';
  }

  String _errorContextLine(String stage) {
    return 'stage=$stage | server=${_activeServerName.toUpperCase()} (${_activeServerIndex + 1}/${_serverQueue.length}) | url=${_shortUrl(_activeVideoUrl)}';
  }

  Future<void> _reportPlaybackFailure({
    required String stage,
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) async {
    final type = stage.toUpperCase();
    final errText = error?.toString().trim();
    final detailText = detail?.trim() ?? '';
    final context = _errorContextLine(stage);
    final message = [
      context,
      if (detailText.isNotEmpty) 'detail=$detailText',
      if (errText != null && errText.isNotEmpty) 'error=$errText',
    ].join(' | ');

    _lastErrorType = type;
    _lastErrorDetail = message;

    await captureAndLogError(
      source: 'video.player.$stage',
      error: message,
      stackTrace: stackTrace,
    );
  }

  void _playIframeEmbed(String url) {
    if (!mounted) return;
    final viewId = 'iframe_player_${DateTime.now().millisecondsSinceEpoch}';
    web_helper.registerIframe(viewId, url);
    setState(() {
      _isIframePlayer = true;
      _iframeViewId = viewId;
      _isLoading = false;
    });
  }

  void _extractAndPlay() {
    _fallbackTimerToken++;
    setState(() {
      _isLoading = true;
      _showNeutralFallback = false;
      _statusMessage =
          'Desencriptando ${_activeServerName.toUpperCase()} (${_activeServerIndex + 1}/${_serverQueue.length})...';
    });
    _resolveFromEmbedHtml().then((resolvedUrls) async {
      if (resolvedUrls.isNotEmpty && !_resolvedVideo) {
        _candidateQueue
          ..clear()
          ..addAll(resolvedUrls);
        final resolvedUrl = _candidateQueue.removeAt(0);
        _resolvedVideo = true;
        _initializePlayer(resolvedUrl);
        return;
      }
      if (_activeVideoUrl.contains('vimeus.com/e/')) {
        final switched = await _tryNextServer(reason: 'vimeus sin embeds detectados');
        if (switched) return;
      }
      if (kIsWeb) {
        _playIframeEmbed(_activeVideoUrl);
      } else if (!kIsWeb && Platform.isWindows) {
        // Skip Windows webview (too slow/unstable), use Flutter webview instead
        _extractWithFlutterWebview();
      } else {
        _extractWithFlutterWebview();
      }

    });
  }

  Future<List<String>> _resolveFromEmbedHtml() async {
    try {
      final dio = Dio();

      // Direct Vimeo / Vimeus config API bypass (blazingly fast native resolution)
      final isVimeusEmbed = _activeVideoUrl.contains('vimeus.com/e/');
      if (isVimeusEmbed) {
        final response = await dio.get<String>(
          ApiClient.wrapUrl(_activeVideoUrl),
          options: Options(
            validateStatus: (status) => status != null && status >= 200 && status < 500,
            headers: kIsWeb ? {} : {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://vimeus.com/',
            },
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        if (response.statusCode != null && response.statusCode! >= 400) {
          await _reportPlaybackFailure(
            stage: 'vimeus-http',
            detail: 'status=${response.statusCode}',
          );
          return const [];
        }
        final html = response.data ?? '';
        final dataRegex = RegExp(r'<script type="text\/json" id="data">([\s\S]*?)<\/script>');
        final match = dataRegex.firstMatch(html);
        if (match != null) {
          final jsonStr = match.group(1)?.trim() ?? '';
          if (jsonStr.isNotEmpty) {
            final data = jsonDecode(jsonStr);
            if (data is Map && data['embeds'] is List) {
              final embeds = data['embeds'] as List;
              final List<String> extractedUrls = [];
              for (var embed in embeds) {
                if (embed is Map && embed['url'] != null) {
                  extractedUrls.add(embed['url'].toString());
                }
              }
              if (extractedUrls.isNotEmpty) {
                return extractedUrls;
              }
            }
          }
        }
      }

      final isVimeo = (_activeVideoUrl.contains('vimeo.com') || 
                      _activeVideoUrl.contains('vimeocdn') || 
                      _activeVideoUrl.contains('vimeus')) && !isVimeusEmbed;
      if (isVimeo) {
        final vimeoIdRegex = RegExp(r'(?:video|channels|groups|album|couches|ondemand|vimeo\.com|vimeus\.com|vimeus)\/([0-9]+)', caseSensitive: false);
        final match = vimeoIdRegex.firstMatch(_activeVideoUrl);
        if (match != null) {
          final vimeoId = match.group(1);
          final configUrl = 'https://player.vimeo.com/video/$vimeoId/config';
          
          final Map<String, String> vimeoHeaders = kIsWeb ? {} : {'User-Agent': 'Mozilla/5.0'};
          if (!kIsWeb && _activeHeaders.containsKey('Referer')) {
            vimeoHeaders['Referer'] = _activeHeaders['Referer']!;
          }
          if (!kIsWeb && _activeHeaders.containsKey('Origin')) {
            vimeoHeaders['Origin'] = _activeHeaders['Origin']!;
          }

          final configResponse = await dio.get(
            ApiClient.wrapUrl(configUrl),
            options: Options(headers: vimeoHeaders),
          );
          if (configResponse.data is Map) {
            final data = configResponse.data as Map;
            final files = data['request']?['files'];
            final List<String> vimeoCandidates = [];
            
            // Check for HLS master stream first
            final hlsData = files?['hls'];
            String? hlsUrl;
            if (hlsData is Map) {
              final cdns = hlsData['cdns'];
              if (cdns is Map && cdns.isNotEmpty) {
                hlsUrl = cdns.values.first['url']?.toString();
              }
              hlsUrl ??= hlsData['default_cdn']?.toString();
            }
            
            if (hlsUrl != null && hlsUrl.isNotEmpty) {
              vimeoCandidates.add(hlsUrl);
            }
            
            // Fallback to progressive MP4 streams
            final progressive = files?['progressive'] as List?;
            if (progressive != null) {
              final sortedProg = List.from(progressive);
              sortedProg.sort((a, b) => (b['width'] as int? ?? 0).compareTo(a['width'] as int? ?? 0));
              for (var file in sortedProg) {
                final mp4Url = file['url']?.toString();
                if (mp4Url != null && mp4Url.isNotEmpty) {
                  vimeoCandidates.add(mp4Url);
                }
              }
            }
            if (vimeoCandidates.isNotEmpty) {
              return vimeoCandidates;
            }
          }
        }
      }
      
      final Map<String, String> requestHeaders = {..._activeHeaders};
      if (kIsWeb) {
        requestHeaders.removeWhere((key, value) {
          final lower = key.toLowerCase();
          return const [
            'user-agent', 'referer', 'origin', 'host', 
            'accept-encoding', 'connection', 'accept', 
            'accept-language', 'cookie', 'sec-fetch-dest',
            'sec-fetch-mode', 'sec-fetch-site'
          ].contains(lower);
        });
      }
      if (!kIsWeb && _activeVideoUrl.contains('h5_player')) {
        requestHeaders['Referer'] = 'https://appnew2.bixplay.online/';
        requestHeaders['Origin'] = 'https://appnew2.bixplay.online';
      }

      final response = await dio.get<String>(
        ApiClient.wrapScraperUrl(_activeVideoUrl),
        options: Options(
          responseType: ResponseType.plain,
          headers: requestHeaders,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status >= 200 && status < 500,
        ),
      );

      final directUri = response.realUri.toString();
      final candidates = <String>[];
      if (_looksLikeStreamUrl(directUri)) {
        candidates.add(directUri);
      }

      final html = response.data ?? '';

      // Direct Bixplay H5 Player Stream Extraction (blazingly fast bypass)
      if (html.contains('STREAM_TOKEN') && html.contains('STREAM_ENDPOINT')) {
        final tokenRegex = RegExp(r'STREAM_TOKEN\s*=\s*"([^"]+)"');
        final endpointRegex = RegExp(r'STREAM_ENDPOINT\s*=\s*"([^"]+)"');
        final tokenMatch = tokenRegex.firstMatch(html);
        final endpointMatch = endpointRegex.firstMatch(html);
        
        if (tokenMatch != null && endpointMatch != null) {
          final streamToken = tokenMatch.group(1)!;
          final streamEndpoint = endpointMatch.group(1)!;
          
          final apiUrl = '$streamEndpoint?action=get_stream&stream_token=${Uri.encodeComponent(streamToken)}';
          final apiRes = await dio.get(
            ApiClient.wrapScraperUrl(apiUrl),
            options: Options(
              headers: kIsWeb ? {} : {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': _activeVideoUrl,
              },
            ),
          );
          
          if (apiRes.data is Map && apiRes.data['streamUrl'] != null) {
            final streamUrl = apiRes.data['streamUrl'].toString();
            if (_looksLikeStreamUrl(streamUrl)) {
              candidates.add(streamUrl);
            }
          }
        }
      }

      // Direct Dean Edwards unpacked stream extraction (Vidhide / Streamwish bypass)
      try {
        final unpacked = _unpackDeanEdwards(html);
        if (unpacked != null) {
          candidates.addAll(_extractStreamCandidatesFromText(unpacked));
        }
      } catch (_) {}

      candidates.addAll(_extractStreamCandidatesFromText(html));
      return _dedupeUrls(candidates);
    } catch (e, st) {
      await _reportPlaybackFailure(stage: 'embed-html', error: e, stackTrace: st);
      return const [];
    }
  }

  List<String> _extractStreamCandidatesFromText(String text) {
    final out = <String>[];
    if (text.isEmpty) return out;

    final normalized = text.replaceAll(r'\/', '/').replaceAll('&amp;', '&').replaceAll('\\u0026', '&');

    // Aggressive URL extraction with multiple patterns
    final urlRegex = RegExp(
      r'''https?:\/\/[^\s"'<>\\`|{}^[\]]+''',
      caseSensitive: false,
    );

    for (final match in urlRegex.allMatches(normalized)) {
      var url = match.group(0)?.trim() ?? '';
      if (url.isEmpty) continue;

      // Clean up trailing characters that shouldn't be part of URL
      while (url.isNotEmpty && RegExp(r'[,;:)]$').hasMatch(url)) {
        url = url.substring(0, url.length - 1);
      }

      if (_looksLikeStreamUrl(url)) {
        out.add(url);
      }
    }

    // Also search for base64-encoded URLs (common in obfuscated pages)
    try {
      final base64Regex = RegExp(r'aHR0cHM/[A-Za-z0-9+/=]+', caseSensitive: false);
      for (final match in base64Regex.allMatches(text)) {
        final encoded = match.group(0) ?? '';
        if (encoded.length > 20) {
          try {
            final decoded = utf8.decode(base64Decode(encoded));
            if (_looksLikeStreamUrl(decoded)) {
              out.add(decoded);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return _dedupeUrls(out);
  }

  List<String> _dedupeUrls(List<String> urls) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in urls) {
      final clean = raw.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean)) out.add(clean);
    }
    return out;
  }

  bool _looksLikeStreamUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();

    // Reject common non-stream files
    if (lower.endsWith('.js') || lower.endsWith('.css') || lower.endsWith('.html') || lower.endsWith('.json')) {
      return false;
    }

    // Skip tracking/analytics URLs
    if (lower.contains('google') || lower.contains('facebook') || lower.contains('analytics')) {
      return false;
    }

    // HLS/DASH manifest patterns
    if (lower.contains('master.m3u8') || lower.contains('playlist.m3u8') ||
        lower.contains('index.m3u8') || lower.contains('stream.m3u8') ||
        lower.contains('livestream.m3u8') || lower.contains('chunklist.m3u8') ||
        lower.contains('manifest.m3u8') || lower.endsWith('.m3u8')) {
      return true;
    }

    // Variant lists
    if (lower.contains('master.txt') || lower.contains('playlist.txt') ||
        lower.contains('chunklist_') || lower.contains('/urlset/')) {
      return true;
    }

    // M3U8 with query params or fragments
    if (lower.contains('.m3u8?') || lower.contains('.m3u8#') ||
        lower.contains('format=m3u8') || lower.contains('type=m3u8') ||
        lower.contains('/m3u8/')) {
      return true;
    }

    // DASH manifests
    if (lower.contains('.mpd') || lower.contains('application/dash')) {
      return true;
    }

    // Progressive MP4
    if (lower.endsWith('.mp4') && !lower.contains('api')) {
      return true;
    }

    // Catch-all for m3u8 but avoid false positives
    if (lower.contains('m3u8') && !lower.contains('.js') && !lower.contains('.css')) {
      return true;
    }

    return false;
  }

  void _startFallbackTimer() {
    final currentToken = ++_fallbackTimerToken;
    final seconds = _nativeCompatibilityMode ? 35 : 20;
    Future.delayed(Duration(seconds: seconds), () {
      if (!mounted || currentToken != _fallbackTimerToken) return;
      if (_isLoading && _videoPlayerController == null) {
        _reportPlaybackFailure(
          stage: 'timeout',
          detail: 'sin stream detectado en el tiempo esperado',
        );
        setState(() {
          _statusMessage = 'No se pudo resolver automaticamente ${_activeServerName.toUpperCase()}.';
          _showNeutralFallback = true;
        });
      }
    });
  }

  void _retryExtraction() {
    if (!mounted) return;
    _fallbackTimerToken++;
    setState(() {
      _retryCount++;
      _statusMessage = _nativeCompatibilityMode
          ? 'Modo compatibilidad nativo activo en ${_activeServerName.toUpperCase()}...'
          : 'Reintentando extraccion en ${_activeServerName.toUpperCase()}...';
      _showNeutralFallback = false;
      _resolvedVideo = false;
      _isIframePlayer = false;
      _iframeViewId = '';
      _candidateQueue.clear();
      _triedCandidates.clear();
      _countdownTimer?.cancel();
      _chewieController?.dispose();
      _chewieController = null;
      _videoPlayerController?.removeListener(_videoListener);
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
    });
    _extractAndPlay();
  }

  Future<void> _extractWithWindowsWebview() async {
    setState(() => _statusMessage = 'Iniciando motor Edge para ${_activeServerName.toUpperCase()}...');
    try {
      // Aggressive timeout: fail fast if Edge doesn't initialize
      await _webviewWindowsController.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Motor Edge no responde (timeout)');
        },
      );
      _webviewWindowsController.url.listen((url) {
        if (!_resolvedVideo && _looksLikeStreamUrl(url)) {
          _resolvedVideo = true;
          _initializePlayer(url);
          _webviewWindowsController.stop();
        }
      });
      await _webviewWindowsController.loadUrl(_activeVideoUrl);
      _startFallbackTimer();
    } catch (e, st) {
      await _reportPlaybackFailure(stage: 'windows-webview', error: e, stackTrace: st);
      _tryNextServer(reason: 'fallo en Webview de Windows');
    }
  }

  void _extractWithFlutterWebview() {
    setState(() => _statusMessage = 'Desencriptando ${_activeServerName.toUpperCase()}...');
    final mergedHeaders = <String, String>{..._activeHeaders};
    mergedHeaders.putIfAbsent('User-Agent', () => 'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    if (!mergedHeaders.containsKey('Referer') && _activeVideoUrl.startsWith('http')) {
      final uri = Uri.tryParse(_activeVideoUrl);
      if (uri != null) {
        mergedHeaders['Referer'] = '${uri.scheme}://${uri.host}/';
        mergedHeaders['Origin'] = '${uri.scheme}://${uri.host}';
      }
    }

    try {
      _webviewFlutterController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('VideoExtractor', onMessageReceived: (message) {
          final url = message.message;
          if (!_resolvedVideo && _looksLikeStreamUrl(url)) {
            _resolvedVideo = true;
            _initializePlayer(url);
          }
        })
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              // Inject XHR/fetch interceptor to capture video URLs
              _webviewFlutterController?.runJavaScript('''
              (function() {
                function notify(u){
                  try{
                    if(!u) return;
                    var s = String(u);
                    if(!/(m3u8|master\\.txt|chunklist|type=m3u8|format=m3u8|\\.urlset|\\.mp4)/i.test(s)) return;
                    VideoExtractor.postMessage(s);
                  }catch(e){}
                }
                var origOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                  notify(url);
                  return origOpen.apply(this, arguments);
                };
                var origFetch = window.fetch;
                window.fetch = function(url, opts) {
                  var finalUrl = '';
                  if (typeof url === 'string') finalUrl = url;
                  else if (url && url.url) finalUrl = url.url;
                  notify(finalUrl);
                  return origFetch.apply(this, arguments);
                };
                var scan = function(root){
                  try{
                    if(!root || !root.querySelectorAll) return;
                    var els = root.querySelectorAll('video,source,iframe');
                    for(var i=0;i<els.length;i++){
                      var n = els[i];
                      notify(n.src || '');
                      if(n.getAttribute){
                        notify(n.getAttribute('data-src') || '');
                      }
                    }
                    var scripts = root.querySelectorAll('script');
                    var r = /(https?:\\/\\/[^\\s"'<>\\\\]+(?:m3u8|mp4|master\\.txt|chunklist[^\\s"'<>\\\\]*))/ig;
                    for(var j=0;j<scripts.length;j++){
                      var c = scripts[j].innerHTML || '';
                      var m;
                      while((m = r.exec(c)) !== null){
                        notify(m[1]);
                      }
                    }
                  }catch(e){}
                };
                scan(document);
                try{
                  var MO=window.MutationObserver||window.WebKitMutationObserver;
                  if(MO){
                    var mo=new MO(function(ms){
                      for(var i=0;i<ms.length;i++){
                        var mm=ms[i];
                        if(mm.type==='attributes' && mm.attributeName==='src' && mm.target){
                          notify(mm.target.src || '');
                        }
                        if(mm.addedNodes){
                          for(var j=0;j<mm.addedNodes.length;j++){
                            var nd=mm.addedNodes[j];
                            if(nd && nd.nodeType===1){ scan(nd); }
                          }
                        }
                      }
                    });
                    mo.observe(document.documentElement||document,{
                      childList:true,
                      subtree:true,
                      attributes:true,
                      attributeFilter:['src']
                    });
                  }
                }catch(e){}
                setInterval(function() {
                  scan(document);
                }, 900);
              })();
            ''');
            },
            onNavigationRequest: (NavigationRequest request) {
              if (!_resolvedVideo && _looksLikeStreamUrl(request.url)) {
                _resolvedVideo = true;
                _initializePlayer(request.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(_activeVideoUrl), headers: mergedHeaders);
      _startFallbackTimer();
    } catch (e, st) {
      _reportPlaybackFailure(stage: 'flutter-webview', error: e, stackTrace: st);
      _tryNextServer(reason: 'fallo al cargar webview');
    }
  }

  Future<bool> _tryNextServer({required String reason}) async {
    if (_activeServerIndex >= _serverQueue.length - 1) {
      await _reportPlaybackFailure(
        stage: 'all-servers-failed',
        detail: 'no hay mas servidores en cola; ultimo_motivo=$reason',
      );
      return false;
    }

    final nextIndex = _activeServerIndex + 1;
    _fallbackTimerToken++;

    _countdownTimer?.cancel();
    _transportOverlayTimer?.cancel();
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _chewieController?.dispose();
    _chewieController = null;

    _resolvedVideo = false;
    _isIframePlayer = false;
    _iframeViewId = '';
    _candidateQueue.clear();
    _triedCandidates.clear();
    _showNeutralFallback = false;
    _isLoading = true;

    _setActiveServer(nextIndex);

    if (mounted) {
      setState(() {
        _statusMessage =
            'Servidor anterior fallo ($reason). Probando ${_activeServerName.toUpperCase()} (${_activeServerIndex + 1}/${_serverQueue.length})...';
      });
    }

    _startPlaybackForActiveServer();
    return true;
  }

  Future<void> _initializePlayer(String url) async {
    final wrappedUrl = ApiClient.wrapUrl(url);
    if (!mounted || _videoPlayerController != null) return;
    if (_triedCandidates.contains(wrappedUrl)) return;
    _triedCandidates.add(wrappedUrl);

    setState(() {
      _statusMessage = 'Cargando video...';
    });

    final Map<String, String> playerHeaders = {..._activeHeaders};
    if (kIsWeb) {
      playerHeaders.removeWhere((key, value) {
        final lower = key.toLowerCase();
        return const [
          'user-agent', 'referer', 'origin', 'host', 
          'accept-encoding', 'connection', 'accept', 
          'accept-language', 'cookie', 'sec-fetch-dest',
          'sec-fetch-mode', 'sec-fetch-site'
        ].contains(lower);
      });
    }

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(wrappedUrl),
      httpHeaders: playerHeaders,
    );

    try {
      await _videoPlayerController!.initialize();
      if (!_resumeApplied && widget.startPositionSeconds > 0) {
        final target = Duration(seconds: widget.startPositionSeconds);
        final total = _videoPlayerController!.value.duration;
        if (total > const Duration(seconds: 10) && target < total - const Duration(seconds: 3)) {
          await _videoPlayerController!.seekTo(target);
        }
        _resumeApplied = true;
      }
      _videoPlayerController!.addListener(_videoListener);
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: true,
        allowFullScreen: true,
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ],
        materialProgressColors: ChewieProgressColors(
          playedColor: colorBrandA,
          handleColor: colorBrandA,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white30,
        ),
        // Note: Full subtitles parsing requires external subtitle file URL
        // Since we don't have the SRT url here, we rely on Chewie's built-in CC if available in m3u8
      );

      setState(() {
        _isLoading = false;
      });
      if (widget.playbackKey.isNotEmpty && _activeVideoUrl.isNotEmpty) {
        await ServerMemory.saveLastWorkingServer(
          playbackKey: widget.playbackKey,
          serverUrl: _activeVideoUrl,
          serverName: _activeServerName,
        );
      }
    } catch (e) {
      if (_candidateQueue.isNotEmpty) {
        final next = _candidateQueue.removeAt(0);
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        _initializePlayer(next);
        return;
      }
      final switched = await _tryNextServer(reason: 'error de reproduccion');
      if (switched) return;
      await _reportPlaybackFailure(stage: 'player-init', error: e);
      setState(() {
        _statusMessage = 'Error al reproducir el video: $e';
        _showNeutralFallback = true;
      });
    }
  }

  String _generatePartyPeerId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final rnd = Random().nextInt(1679616).toRadixString(36).toUpperCase().padLeft(4, '0');
    return 'P$ts$rnd';
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final out = StringBuffer();
    for (int i = 0; i < 6; i++) {
      out.write(chars[rand.nextInt(chars.length)]);
    }
    return out.toString();
  }

  String _normalizeRoomCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length <= 6) return cleaned;
    return cleaned.substring(0, 6);
  }

  String _currentMediaKeyForParty() {
    final id = widget.mediaId?.trim() ?? '';
    final type = widget.mediaType?.trim() ?? '';
    if (id.isNotEmpty && type.isNotEmpty) return '$type:$id';
    if (widget.playbackKey.trim().isNotEmpty) return widget.playbackKey.trim();
    return widget.videoUrl;
  }

  WatchPartySession? _currentPartySessionSnapshot() {
    final service = _partyService;
    if (service == null || !service.isConnected || _partyRoomId.isEmpty) return null;
    return WatchPartySession(
      roomId: _partyRoomId,
      peerName: _partyPeerName,
      isHost: _partyIsHost,
    );
  }

  bool _partyBroadcastAllowed() {
    if (_partyService == null || !_partyService!.isConnected) return false;
    if (_partyApplyingRemote) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= _partySuppressBroadcastUntilMs;
  }

  void _pushCurrentMediaStateToParty() {
    final service = _partyService;
    final player = _videoPlayerController;
    if (service == null || !_partyIsHost || player == null) return;
    final value = player.value;
    if (!value.isInitialized) return;
    service.setMedia(
      mediaKey: _currentMediaKeyForParty(),
      currentUrl: _activeVideoUrl,
    );
    service.sendSync(
      action: value.isPlaying ? 'play' : 'pause',
      positionMs: value.position.inMilliseconds,
      isPlaying: value.isPlaying,
    );
  }

  Future<void> _applyPartyStateSnapshot(Map<String, dynamic> state) async {
    if (_partyIsHost) return;
    final player = _videoPlayerController;
    if (player == null) return;
    final value = player.value;
    if (!value.isInitialized) return;

    final mediaKey = (state['mediaKey'] ?? '').toString();
    if (mediaKey.isNotEmpty && mediaKey != _currentMediaKeyForParty()) {
      if (mounted) {
        setState(() {
          _partyStatus = 'La sala esta viendo otro contenido';
        });
      }
      return;
    }

    final remotePos = (state['positionMs'] as num?)?.toInt() ?? 0;
    final remotePlaying = state['isPlaying'] == true;
    final currentMs = value.position.inMilliseconds;
    final drift = (currentMs - remotePos).abs();

    _partyApplyingRemote = true;
    _partySuppressBroadcastUntilMs = DateTime.now().millisecondsSinceEpoch + 1600;
    try {
      if (drift > 1200) {
        await player.seekTo(Duration(milliseconds: remotePos));
      }
      if (remotePlaying && !player.value.isPlaying) {
        await player.play();
      } else if (!remotePlaying && player.value.isPlaying) {
        await player.pause();
      }
    } finally {
      _partyApplyingRemote = false;
    }
  }

  void _showTransportOverlay(String label) {
    _transportOverlayTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _transportOverlayText = label;
    });
    _transportOverlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _transportOverlayText = '';
      });
    });
  }

  Future<void> _seekBySeconds(int deltaSeconds) async {
    final controller = _videoPlayerController;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;

    final current = value.position.inSeconds;
    final total = value.duration.inSeconds;
    final targetSeconds = (current + deltaSeconds).clamp(0, total > 1 ? total - 1 : 0);
    await controller.seekTo(Duration(seconds: targetSeconds));
    _partyLastSentPositionMs = targetSeconds * 1000;
    _showTransportOverlay(deltaSeconds >= 0 ? '+${deltaSeconds}s' : '${deltaSeconds}s');
  }

  Future<void> _togglePlayPause() async {
    final controller = _videoPlayerController;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      await controller.pause();
      _showTransportOverlay('Pausa');
    } else {
      await controller.play();
      _showTransportOverlay('Reproducir');
    }
  }

  Future<void> _restartPlayback() async {
    final controller = _videoPlayerController;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    await controller.seekTo(Duration.zero);
    _partyLastSentPositionMs = 0;
    _showTransportOverlay('Inicio');
  }

  KeyEventResult _handlePlayerKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _isLoading) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBySeconds(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBySeconds(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBySeconds(30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBySeconds(-30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _restartPlayback();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      if (mounted) {
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showWatchPartyDialog() async {
    final roomController = TextEditingController(text: _partyRoomId);
    final nameController = TextEditingController(text: _partyPeerName);
    bool createMode = _partyRoomId.isEmpty;
    bool hostMode = _partyIsHost;
    String info = _partyStatus;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111118),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Watch Party', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Crear sala'),
                          selected: createMode,
                          onSelected: (_) => setDialogState(() {
                            createMode = true;
                            hostMode = true;
                          }),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text('Unirse'),
                          selected: !createMode,
                          onSelected: (_) => setDialogState(() {
                            createMode = false;
                            hostMode = false;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Tu nombre',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roomController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: createMode ? 'Codigo (auto)' : 'Codigo de sala',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'Ej: AB12CD',
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                      enabled: !createMode,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      info,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_partyService != null)
                  TextButton(
                    onPressed: () async {
                      await _leaveWatchParty();
                      if (!mounted) return;
                      setDialogState(() {
                        info = 'Sala cerrada.';
                        roomController.text = '';
                      });
                    },
                    child: const Text('Salir de sala'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                ElevatedButton(
                  onPressed: _partyConnecting
                      ? null
                      : () async {
                          final peerName = nameController.text.trim().isEmpty
                              ? 'Invitado'
                              : nameController.text.trim();
                          final room = createMode
                              ? _generateRoomCode()
                              : _normalizeRoomCode(roomController.text);
                          if (room.isEmpty || room.length < 4) {
                            setDialogState(() {
                              info = 'Codigo invalido.';
                            });
                            return;
                          }
                          roomController.text = room;
                          setDialogState(() {
                            info = createMode
                                ? 'Creando sala $room...'
                                : 'Uniendote a $room...';
                          });
                          await _joinWatchParty(
                            roomId: room,
                            peerName: peerName,
                            isHost: createMode || hostMode,
                          );
                          if (!mounted) return;
                          setDialogState(() {
                            info = _partyStatus;
                          });
                        },
                  child: Text(createMode ? 'Crear y conectar' : 'Unirme'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _joinWatchParty({
    required String roomId,
    required String peerName,
    required bool isHost,
  }) async {
    if (_partyConnecting) return;
    _partyConnecting = true;
    setState(() {
      _partyStatus = 'Conectando a sala...';
    });

    try {
      await _leaveWatchParty(notify: false);

      final normalizedRoom = _normalizeRoomCode(roomId);
      final peer = peerName.trim().isEmpty ? 'Invitado' : peerName.trim();
      final service = WatchPartyService(
        roomId: normalizedRoom,
        peerId: _partyPeerId,
        peerName: peer,
        isHost: isHost,
      );
      _partySubscription = service.events.listen(_onPartyEvent);
      await service.connect();

      _partyService = service;
      _partyRoomId = normalizedRoom;
      _partyPeerName = peer;
      _partyIsHost = isHost;
      _partyMembers = 1;
      _partyStatus = 'Conectando...';

      _partyHeartbeatTimer?.cancel();
      _partyHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final player = _videoPlayerController;
        final srv = _partyService;
        if (player == null || srv == null || !srv.isConnected) return;
        final v = player.value;
        if (!v.isInitialized) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _partyLastHeartbeatMs < 1800) return;
        _partyLastHeartbeatMs = now;

        if (_partyIsHost) {
          srv.sendSync(
            action: v.isPlaying ? 'play' : 'pause',
            positionMs: v.position.inMilliseconds,
            isPlaying: v.isPlaying,
          );
        }
      });

      _pushCurrentMediaStateToParty();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sala activa: $_partyRoomId')),
        );
      }

      if (_partyIsHost) {
        final invite = 'Mira conmigo en Zuper. Sala: $_partyRoomId';
        await Clipboard.setData(ClipboardData(text: invite));
      }
    } catch (e) {
      _partyStatus = 'No se pudo conectar: $e';
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_partyStatus)),
        );
      }
    } finally {
      _partyConnecting = false;
      if (mounted) setState(() {});
    }
  }

  void _onPartyEvent(WatchPartyEvent event) {
    if (!mounted) return;

    if (event.type == 'welcome') {
      final state = event.payload['state'];
      if (state is Map) {
        final roster = state['roster'];
        if (roster is List) {
          _partyMembers = roster.length.clamp(1, 99);
        }
        Future<void>(() async {
          await _applyPartyStateSnapshot(Map<String, dynamic>.from(state));
        });
      }
      setState(() {
        _partyStatus = 'Sala activa • $_partyMembers participante${_partyMembers != 1 ? 's' : ''}';
      });

      if (_partyIsHost) {
        final invite = 'Mira conmigo en Zuper. Sala: $_partyRoomId';
        Clipboard.setData(ClipboardData(text: invite));
        _pushCurrentMediaStateToParty();
      }
      return;
    }

    if (event.type == 'roster_updated') {
      final roster = event.payload['roster'];
      if (roster is List) {
        _partyMembers = roster.length.clamp(1, 99);
      }
      setState(() {
        _partyStatus = 'Sala activa • $_partyMembers participante${_partyMembers != 1 ? 's' : ''}';
      });
      return;
    }

    if (event.type == 'host_changed') {
      final newHostId = event.payload['hostId'];
      if (newHostId == _partyPeerId) {
        _partyIsHost = true;
        setState(() {
          _partyStatus = 'Eres el anfitrión ahora';
        });
      }
      return;
    }

    if (event.type == 'media_changed') {
      final mediaKey = event.payload['mediaKey']?.toString() ?? '';
      if (mediaKey.isNotEmpty && !_partyIsHost) {
        setState(() {
          _partyStatus = 'Contenido cambió (anfitrión)';
        });
      }
      return;
    }

    if (event.type == 'error') {
      final message = event.payload['message']?.toString() ?? 'Error de sala';
      setState(() {
        _partyStatus = message;
      });
      return;
    }

    if (event.type == 'closed') {
      setState(() {
        _partyStatus = 'Desconectado';
      });
      return;
    }

    if (event.type != 'sync') return;

    // Solo aplicar sync si no eres host
    if (_partyIsHost) return;

    final payload = event.payload;
    final player = _videoPlayerController;
    if (player == null || !player.value.isInitialized) return;

    final remotePos = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final isPlaying = payload['isPlaying'] == true;
    final action = payload['action']?.toString() ?? (isPlaying ? 'play' : 'pause');
    final sentAtMs = (payload['sentAtMs'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final latency = sentAtMs > 0 ? (now - sentAtMs) : 0;
    final expectedPos = remotePos + (isPlaying && latency > 0 ? latency.clamp(0, 500) : 0);

    _partyApplyingRemote = true;
    _partySuppressBroadcastUntilMs = now + 1600;

    Future<void>(() async {
      try {
        final currentMs = player.value.position.inMilliseconds;
        final drift = (currentMs - expectedPos).abs();
        if (drift > 1500) {
          await player.seekTo(Duration(milliseconds: expectedPos));
        }

        if (action == 'seek') {
          await player.seekTo(Duration(milliseconds: expectedPos));
        }
        if (isPlaying && !player.value.isPlaying) {
          await player.play();
        } else if (!isPlaying && player.value.isPlaying) {
          await player.pause();
        }
      } catch (_) {
      } finally {
        _partyApplyingRemote = false;
      }
    });
  }

  Future<void> _leaveWatchParty({bool notify = true}) async {
    _partyHeartbeatTimer?.cancel();
    _partyHeartbeatTimer = null;
    await _partySubscription?.cancel();
    _partySubscription = null;
    await _partyService?.dispose();
    _partyService = null;
    _partyMembers = 1;
    _partyRoomId = '';
    if (notify) {
      _partyStatus = 'Sin sala';
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _broadcastPartySyncIfNeeded(VideoPlayerValue value) {
    final service = _partyService;
    if (service == null || !service.isConnected) return;
    if (!_partyBroadcastAllowed()) return;
    if (!value.isInitialized) return;

    final nowPos = value.position.inMilliseconds;
    final nowPlaying = value.isPlaying;
    if (_partyLastPlayingState == null || _partyLastPlayingState != nowPlaying) {
      service.sendSync(
        action: nowPlaying ? 'play' : 'pause',
        positionMs: nowPos,
        isPlaying: nowPlaying,
      );
      _partyLastPlayingState = nowPlaying;
      _partyLastSentPositionMs = nowPos;
      return;
    }

    final moved = (nowPos - _partyLastSentPositionMs).abs();
    if (moved >= 3000) {
      service.sendSync(
        action: 'seek',
        positionMs: nowPos,
        isPlaying: nowPlaying,
      );
      _partyLastSentPositionMs = nowPos;
    }
  }

  @override
  void dispose() {
    final value = _videoPlayerController?.value;
    if (value != null && value.isInitialized) {
      _saveWatchProgressIfNeeded(
        position: value.position,
        duration: value.duration,
        force: true,
        completed: false,
      );
    }
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _countdownTimer?.cancel();
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    if (!kIsWeb && Platform.isWindows) {
      _webviewWindowsController.dispose();
    }

    _leaveWatchParty(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTV = MediaQuery.of(context).size.width > 960;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => _handlePlayerKeyEvent(event),
        child: Stack(
          children: [
            Center(
              child: _isLoading
                  ? (_showNeutralFallback
                      ? _buildNeutralFallback(isTV)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: colorBrandA),
                            const SizedBox(height: 20),
                            Text(_statusMessage, style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 8),
                            Text(
                              'Servidor: ${_activeServerName.toUpperCase()} (${_activeServerIndex + 1}/${_serverQueue.length})',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            // Hidden Webview for extraction
                            if (!_looksLikeStreamUrl(_activeVideoUrl))
                              SizedBox(
                                width: 1,
                                height: 1,
                                child: kIsWeb
                                    ? const SizedBox.shrink()
                                    : (!kIsWeb && Platform.isWindows
                                        ? Webview(_webviewWindowsController)
                                        : (_webviewFlutterController != null
                                            ? WebViewWidget(controller: _webviewFlutterController!)
                                            : const SizedBox.shrink())),

                              ),
                          ],
                        ))
                  : (_isIframePlayer
                      ? HtmlElementView(viewType: _iframeViewId)
                      : Chewie(controller: _chewieController!)),
            ),
            _buildNextEpisodeCountdownCard(isTV),
            _buildRecommendationsScreen(isTV),
            Positioned(
              top: isTV ? 26 : 14,
              right: isTV ? 24 : 12,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isLoading)
                      IconButton(
                        icon: const Icon(Icons.cast_rounded, color: Colors.white, size: 28),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (context) => CastDeviceDialog(
                              videoUrl: _activeVideoUrl,
                              videoTitle: widget.mediaTitle ?? 'Video',
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 8),
                    _buildWatchPartyChip(isTV),
                  ],
                ),
              ),
            ),
            if (_transportOverlayText.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: EdgeInsets.symmetric(
                        horizontal: isTV ? 24 : 18,
                        vertical: isTV ? 14 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _transportOverlayText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTV ? 26 : 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchPartyChip(bool isTV) {
    return const SizedBox.shrink();
  }

  Widget _buildNeutralFallback(bool isTV) {
    final hasNextServer = _activeServerIndex < _serverQueue.length - 1;
    return Padding(
      padding: EdgeInsets.all(isTV ? 28 : 16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: EdgeInsets.all(isTV ? 24 : 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se pudo desencriptar automaticamente',
              style: TextStyle(
                color: Colors.white,
                fontSize: isTV ? 24 : 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isTV ? 12 : 8),
            Text(
              'Servidor complicado o lento. Podes reintentar o usar un modo nativo mas estricto.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: isTV ? 18 : 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Actual: ${_activeServerName.toUpperCase()} (${_activeServerIndex + 1}/${_serverQueue.length})',
              style: TextStyle(
                color: Colors.white60,
                fontSize: isTV ? 15 : 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Tipo de error: $_lastErrorType',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: isTV ? 14 : 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (_lastErrorDetail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  _lastErrorDetail,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: isTV ? 12 : 11,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (_retryCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Reintentos: $_retryCount',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
            SizedBox(height: isTV ? 22 : 14),
            FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fallbackBtn(
                    label: 'Reintentar extraccion',
                    icon: Icons.refresh,
                    isTV: isTV,
                    autofocus: true,
                    onPressed: () {
                      _nativeCompatibilityMode = false;
                      _retryExtraction();
                    },
                  ),
                  const SizedBox(height: 10),
                  _fallbackBtn(
                    label: 'Ingresar URL manualmente',
                    icon: Icons.link,
                    isTV: isTV,
                    onPressed: _showManualStreamInput,
                  ),
                  const SizedBox(height: 10),
                  _fallbackBtn(
                    label: 'Copiar detalle error',
                    icon: Icons.copy_rounded,
                    isTV: isTV,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _lastErrorDetail.isEmpty ? _statusMessage : _lastErrorDetail));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Detalle de error copiado.')),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _fallbackBtn(
                    label: 'Modo compatibilidad nativo',
                    icon: Icons.shield_outlined,
                    isTV: isTV,
                    onPressed: () {
                      _nativeCompatibilityMode = true;
                      _retryExtraction();
                    },
                  ),
                  if (hasNextServer) ...[
                    const SizedBox(height: 10),
                    _fallbackBtn(
                      label: 'Probar siguiente servidor',
                      icon: Icons.skip_next_rounded,
                      isTV: isTV,
                      onPressed: () {
                        _tryNextServer(reason: 'cambio manual');
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  _fallbackBtn(
                    label: 'Volver y cambiar servidor',
                    icon: Icons.arrow_back,
                    isTV: isTV,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualStreamInput() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ingresar URL del stream', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'https://ejemplo.com/stream.m3u8',
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorBrandA, width: 2),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Text(
                'Pegá la URL del stream (m3u8, mp4, etc)',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
                Navigator.pop(context, url);
              }
            },
            child: const Text('Cargar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      _initializePlayer(result);
    }
  }

  String? _unpackDeanEdwards(String html) {
    final regex = RegExp(
      r"\}\s*\(\s*'([\s\S]*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([\s\S]*?)'\.split\('\|'\)",
      caseSensitive: false,
    );
    
    final match = regex.firstMatch(html);
    if (match == null) return null;
    
    final p = match.group(1) ?? '';
    final a = int.tryParse(match.group(2) ?? '') ?? 36;
    final k = (match.group(4) ?? '').split('|');
    
    String unbase(int num, int base) {
      const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      if (num == 0) return '0';
      var res = '';
      var n = num;
      while (n > 0) {
        res = chars[n % base] + res;
        n = n ~/ base;
      }
      return res;
    }
    
    final Map<String, String> replacements = {};
    for (int i = 0; i < k.length; i++) {
      if (k[i].isNotEmpty) {
        final key = unbase(i, a);
        replacements[key] = k[i];
      }
    }
    
    final wordRegex = RegExp(r'\b[a-zA-Z0-9]+\b');
    final unpacked = p.replaceAllMapped(wordRegex, (m) {
      final word = m.group(0)!;
      return replacements[word] ?? word;
    });
    
    return unpacked;
  }

  Widget _fallbackBtn({
    required String label,
    required IconData icon,
    required bool isTV,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        autofocus: autofocus,
        onPressed: onPressed,
        icon: Icon(icon, size: isTV ? 28 : 20),
        label: Padding(
          padding: EdgeInsets.symmetric(vertical: isTV ? 14 : 10),
          child: Text(
            label,
            style: TextStyle(fontSize: isTV ? 20 : 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  // --- AUTOPLAY NEXT EPISODE & RECOMMENDATIONS ENGINE ---

  void _videoListener() {
    if (!mounted || _videoPlayerController == null) return;
    
    final value = _videoPlayerController!.value;
    if (!value.isInitialized) return;
    
    final position = value.position;
    final duration = value.duration;
    
    if (duration == Duration.zero) return;

    final remaining = duration - position;

    final hasNext = widget.episodesList != null &&
        widget.currentEpisodeIndex != null &&
        widget.currentEpisodeIndex! < widget.episodesList!.length - 1;

    if (widget.mediaType == 'tvseries' && hasNext) {
      if (remaining.inSeconds <= 20 && remaining.inSeconds > 0 && !_countdownActive && !_showRecommendations) {
        _startNextEpisodeCountdown();
      }
    }

    _saveWatchProgressIfNeeded(
      position: position,
      duration: duration,
      force: false,
      completed: false,
    );
    _broadcastPartySyncIfNeeded(value);

    if ((value.isCompleted || position >= duration - const Duration(milliseconds: 500)) && !_showRecommendations) {
      _handlePlaybackFinished();
    }
  }

  String _resolveMediaId() {
    final explicit = widget.mediaId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;

    final key = widget.playbackKey.trim();
    if (key.isEmpty) return '';
    final parts = key.split(':');
    if (parts.length >= 2) {
      return parts[1].trim();
    }
    return '';
  }

  List<Map<String, dynamic>> _serializeServerQueueForHistory() {
    final out = <Map<String, dynamic>>[];
    for (final s in _serverQueue) {
      final url = s['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final rawHeaders = s['headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) {
          if (k != null && v != null) {
            headers[k.toString()] = v.toString();
          }
        });
      }
      out.add({
        'name': s['name']?.toString() ?? 'SERVIDOR',
        'url': url,
        'serverType': s['serverType']?.toString() ?? '',
        'headers': headers,
      });
    }
    return out;
  }

  void _saveWatchProgressIfNeeded({
    required Duration position,
    required Duration duration,
    required bool force,
    required bool completed,
  }) {
    final playbackKey = widget.playbackKey.trim();
    if (playbackKey.isEmpty) return;
    final durationSeconds = duration.inSeconds;
    final positionSeconds = position.inSeconds;
    if (durationSeconds <= 0) return;

    if (!force) {
      if (positionSeconds <= 5) return;
      if (_lastProgressSavedAtSecond >= 0 && (positionSeconds - _lastProgressSavedAtSecond) < 12) {
        return;
      }
    }

    _lastProgressSavedAtSecond = positionSeconds;
    final mediaType = (widget.mediaType ?? '').trim();
    final mediaId = _resolveMediaId();
    final title = (widget.mediaTitle ?? '').trim();
    final posterUrl = (widget.mediaPosterUrl ?? '').trim();
    final queue = _serializeServerQueueForHistory();
    final activeUrl = _activeVideoUrl.trim();

    Future<void>(() async {
      await WatchHistoryService.saveProgress(
        playbackKey: playbackKey,
        mediaType: mediaType,
        mediaId: mediaId,
        title: title,
        posterUrl: posterUrl,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        videoUrl: activeUrl,
        headers: Map<String, String>.from(_activeHeaders),
        serverQueue: queue,
        completed: completed,
      );
    });
  }

  void _startNextEpisodeCountdown() {
    setState(() {
      _countdownActive = true;
      _countdownSeconds = 20;
      _showNextEpisodeOverlay = true;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          timer.cancel();
          _countdownActive = false;
          _showNextEpisodeOverlay = false;
          _playNextEpisode();
        }
      });
    });
  }

  void _cancelNextEpisodeCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownActive = false;
      _showNextEpisodeOverlay = false;
    });
  }

  void _playNextEpisodeImmediately() {
    _countdownTimer?.cancel();
    _countdownActive = false;
    setState(() {
      _showNextEpisodeOverlay = false;
    });
    _playNextEpisode();
  }

  Future<void> _playNextEpisode() async {
    if (_isResolvingNextEpisode) return;
    
    final nextIndex = widget.currentEpisodeIndex! + 1;
    if (widget.episodesList == null || nextIndex >= widget.episodesList!.length) {
      _handlePlaybackFinished();
      return;
    }

    setState(() {
      _isResolvingNextEpisode = true;
      _isLoading = true;
      _statusMessage = 'Preparando siguiente episodio...';
    });

    try {
      await _videoPlayerController?.pause();
    } catch (_) {}

    final nextEpisode = widget.episodesList![nextIndex];

    List<Map<String, dynamic>> servers = [];
    final headers = _extractHeaders(nextEpisode);
    
    final directUrl = nextEpisode['file_url']?.toString() ?? '';
    final directLabel = nextEpisode['label']?.toString() ?? 'SERVIDOR 1';
    if (directUrl.isNotEmpty) {
      servers.add({'name': directLabel.toUpperCase(), 'url': directUrl, 'headers': headers});
    }
    
    if (nextEpisode['videos'] != null && nextEpisode['videos'] is List) {
      for (var vid in nextEpisode['videos']) {
        final url = vid['file_url']?.toString() ?? '';
        final label = vid['label']?.toString() ?? 'SERVIDOR';
        if (url.isNotEmpty) {
          servers.add({
            'name': label.toUpperCase(),
            'url': url,
            'headers': _extractHeaders(vid)
          });
        }
      }
    }

    try {
      final finalized = await _resolveAndFinalizeServers(servers);
      if (!mounted) return;

      if (finalized.isEmpty) {
        setState(() {
          _isResolvingNextEpisode = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron servidores para el siguiente episodio.')),
        );
        _handlePlaybackFinished();
        return;
      }

      _countdownTimer?.cancel();
      _videoPlayerController?.removeListener(_videoListener);
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
      _chewieController?.dispose();
      _chewieController = null;

      final first = finalized.first;
      final url = first['url'] as String;
      final fHeaders = first['headers'] as Map<String, String>;
      final isDirect = _isDirectStreamUrl(url);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: url,
            isDirect: isDirect,
            headers: fHeaders,
            serverQueue: finalized,
            episodesList: widget.episodesList,
            currentEpisodeIndex: nextIndex,
            mediaTitle: widget.mediaTitle,
            mediaType: widget.mediaType,
            mediaId: widget.mediaId,
            mediaPosterUrl: widget.mediaPosterUrl,
            playbackKey: widget.playbackKey,
            startPositionSeconds: 0,
            initialWatchPartySession: _currentPartySessionSnapshot(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResolvingNextEpisode = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar el siguiente episodio: $e')),
        );
        _handlePlaybackFinished();
      }
    }
  }

  void _handlePlaybackFinished() {
    _countdownTimer?.cancel();
    _countdownActive = false;
    _showNextEpisodeOverlay = false;

    final value = _videoPlayerController?.value;
    if (value != null && value.isInitialized) {
      _saveWatchProgressIfNeeded(
        position: value.position,
        duration: value.duration,
        force: true,
        completed: true,
      );
    }

    try {
      _videoPlayerController?.pause();
    } catch (_) {}

    setState(() {
      _showRecommendations = true;
    });
  }

  Future<void> _loadRecommendations() async {
    try {
      final client = ApiClient();
      List<dynamic> rawList = [];
      if (widget.mediaType == 'tvseries') {
        rawList = await client.getTvSeries(page: 1);
      } else {
        rawList = await client.getMovies(page: 1);
      }
      
      if (rawList.isNotEmpty) {
        rawList.shuffle();
        setState(() {
          _recommendations = rawList.take(4).toList();
          _loadingRecommendations = false;
        });
      } else {
        setState(() {
          _loadingRecommendations = false;
        });
      }
    } catch (e) {
      await captureAndLogError(source: 'player.loadRecommendations', error: e);
      setState(() {
        _loadingRecommendations = false;
      });
    }
  }

  Widget _buildNextEpisodeCountdownCard(bool isTV) {
    if (!_showNextEpisodeOverlay) return const SizedBox.shrink();

    final nextIndex = widget.currentEpisodeIndex! + 1;
    if (widget.episodesList == null || nextIndex >= widget.episodesList!.length) return const SizedBox.shrink();

    final nextEpisode = widget.episodesList![nextIndex];
    final epTitle = nextEpisode['episodes_name'] ?? 'Siguiente Episodio';

    return Positioned(
      bottom: isTV ? 40 : 20,
      right: isTV ? 40 : 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            width: isTV ? 380 : 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F18).withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorBrandA.withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Siguiente episodio en ${_countdownSeconds}s...',
                        style: TextStyle(
                          color: colorBrandA,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  epTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTV ? 18 : 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildOverlayButton(
                        label: 'Reproducir Ya',
                        isPrimary: true,
                        isTV: isTV,
                        onTap: _playNextEpisodeImmediately,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildOverlayButton(
                        label: 'Cancelar',
                        isPrimary: false,
                        isTV: isTV,
                        onTap: _cancelNextEpisodeCountdown,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required String label,
    required bool isPrimary,
    required bool isTV,
    required VoidCallback onTap,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: focused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
              transformAlignment: Alignment.center,
              padding: EdgeInsets.symmetric(vertical: isTV ? 12 : 8),
              decoration: BoxDecoration(
                gradient: isPrimary
                    ? LinearGradient(colors: [colorBrandB, colorBrandA],
                      )
                    : null,
                color: isPrimary ? null : (focused ? Colors.white12 : Colors.white10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused
                      ? (isPrimary ? Colors.white : colorBrandA)
                      : Colors.transparent,
                  width: 2.0,
                ),
                boxShadow: focused && isPrimary
                    ? [
                        BoxShadow(
                          color: colorBrandA.withOpacity(0.4),
                          blurRadius: 10,
                        )
                      ]
                    : [],
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: isTV ? 15 : 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecommendationsScreen(bool isTV) {
    if (!_showRecommendations) return const SizedBox.shrink();

    final title = widget.mediaTitle ?? 'Contenido';

    return Container(
      color: Colors.black.withOpacity(0.4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
        child: Container(
          color: const Color(0xFF0A0A0D).withOpacity(0.85),
          padding: EdgeInsets.symmetric(horizontal: isTV ? 64 : 24, vertical: isTV ? 40 : 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Has terminado de ver',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: isTV ? 18 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTV ? 32 : 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Container(
                width: 80,
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorBrandB, colorBrandA],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '¿QUÉ VER AHORA?',
                style: TextStyle(
                  color: colorBrandA,
                  fontSize: isTV ? 20 : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              
              _loadingRecommendations
                  ? Center(child: CircularProgressIndicator(color: colorBrandA))
                  : _recommendations.isEmpty
                      ? const Text(
                          'No hay recomendaciones disponibles.',
                          style: TextStyle(color: Colors.white54),
                        )
                      : Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: _recommendations.map((item) {
                                return _buildRecommendationCard(item, isTV);
                              }).toList(),
                            ),
                          ),
                        ),
                        
              const SizedBox(height: 40),
              
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.select)) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        transform: focused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                        transformAlignment: Alignment.center,
                        padding: EdgeInsets.symmetric(horizontal: isTV ? 32 : 20, vertical: isTV ? 14 : 10),
                        decoration: BoxDecoration(
                          color: focused ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused ? colorBrandA : Colors.transparent,
                            width: 2.0,
                          ),
                        ),
                        child: Text(
                          'Volver al Inicio',
                          style: TextStyle(
                            color: focused ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isTV ? 16 : 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(dynamic item, bool isTV) {
    final title = item['title'] ?? item['tv_name'] ?? 'Contenido';
    final posterUrl = item['poster_url'] ?? item['image_url'] ?? '';
    
    final type = (item['is_tvseries']?.toString() == '1' || item['tv_name'] != null)
        ? 'tvseries'
        : 'movies';
    
    final id = (item['videos_id'] ?? item['movies_id'] ?? item['live_tv_id'] ?? item['stream_id'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.select)) {
            _navigateToRecommendation(item, type, id);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: () => _navigateToRecommendation(item, type, id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                transform: focused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                transformAlignment: Alignment.center,
                width: isTV ? 150 : 100,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: isTV ? 210 : 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: focused ? colorBrandA : const Color(0xFF1F1F30),
                          width: focused ? 3.0 : 1.5,
                        ),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color: colorBrandA.withOpacity(0.35),
                                  blurRadius: 15,
                                  spreadRadius: 1,
                                )
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: posterUrl.isNotEmpty
                            ? Image.network(
                                posterUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (c, e, s) => Container(
                                  color: const Color(0xFF0F0F18),
                                  child: const Icon(Icons.movie_creation_outlined, color: Colors.white54),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF0F0F18),
                                child: const Icon(Icons.movie_creation_outlined, color: Colors.white54),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: focused ? colorBrandA : Colors.white70,
                        fontSize: isTV ? 13 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _navigateToRecommendation(dynamic item, String type, String id) {
    _countdownTimer?.cancel();
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          itemData: item,
          type: type,
          id: id,
        ),
      ),
    );
  }

  bool _isDirectStreamUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm');
  }

  // --- BACKGROUND NEXT EPISODE RESOLVER METHODS ---

  Map<String, String> _extractHeaders(dynamic item) {
    Map<String, String> headers = {};
    for (int i = 1; i <= 8; i++) {
      final key = item['header$i']?.toString() ?? '';
      final val = item['header${i}Value']?.toString() ?? '';
      if (key.isNotEmpty && val.isNotEmpty) {
        if (val.toLowerCase().contains('example.com')) continue;
        headers[key] = val;
      }
    }
    return headers;
  }

  Future<List<Map<String, dynamic>>> _resolveMultipleRapido(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        ApiClient.wrapUrl(url),
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 9; G011A Build/PI) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/68.0.3440.70 Mobile Safari/537.36 buscari/53',
            'Referer': 'https://appnew2.bixplay.online/',
          },
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      
      final html = response.data ?? '';
      final out = <Map<String, dynamic>>[];
      
      final linkRegex = RegExp(r'data-link="([^"]+)"', caseSensitive: false);
      final nameRegex = RegExp(r'data-name="([^"]+)"', caseSensitive: false);
      
      final divRegex = RegExp(r'<div\b[^>]*class="[^"]*server-card[^"]*"[^>]*>', caseSensitive: false);
      for (final match in divRegex.allMatches(html)) {
        final tagHtml = match.group(0) ?? '';
        final linkMatch = linkRegex.firstMatch(tagHtml);
        final nameMatch = nameRegex.firstMatch(tagHtml);
        
        if (linkMatch != null && nameMatch != null) {
          final link = linkMatch.group(1) ?? '';
          final name = nameMatch.group(1) ?? 'Servidor';
          if (link.isNotEmpty) {
            out.add({
              'name': '${name.toUpperCase()} (RÁPIDO)',
              'url': link,
              'headers': {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://server.bixplay.online/',
                'Origin': 'https://server.bixplay.online',
              }
            });
          }
        }
      }
      
      if (out.isEmpty) {
        final fallbackRegex = RegExp(r'data-link="([^"]+)"[^>]*data-name="([^"]+)"', caseSensitive: false);
        for (final match in fallbackRegex.allMatches(html)) {
          final link = match.group(1) ?? '';
          final name = match.group(2) ?? 'Servidor';
          if (link.isNotEmpty) {
            out.add({
              'name': '${name.toUpperCase()} (RÁPIDO)',
              'url': link,
              'headers': {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://server.bixplay.online/',
                'Origin': 'https://server.bixplay.online',
              }
            });
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _resolveAndFinalizeServers(List<Map<String, dynamic>> rawServers) async {
    final expanded = <Map<String, dynamic>>[];

    for (final raw in rawServers) {
      final normalized = _normalizeServer(raw);
      if ((normalized['url'] as String).isEmpty) continue;
      if (_isMultiplePortalServer(normalized)) {
        final nested = await _resolveMultipleRapido(normalized['url'] as String);
        if (nested.isNotEmpty) {
          expanded.addAll(nested.map(_normalizeServer));
          continue;
        }
      }
      expanded.add(normalized);
    }

    final deduped = _dedupeServers(expanded);
    deduped.sort((a, b) => _serverPriority(a).compareTo(_serverPriority(b)));
    return deduped;
  }

  bool _isMultiplePortalServer(Map<String, dynamic> server) {
    final url = server['url']?.toString().toLowerCase() ?? '';
    final label = server['name']?.toString().toUpperCase() ?? '';
    return url.contains('server.bixplay.online/server-nuevo-v2') || label.contains('MULTIPLE');
  }

  int _serverPriority(Map<String, dynamic> server) {
    final name = server['name']?.toString().toUpperCase() ?? '';
    final url = server['url']?.toString().toLowerCase() ?? '';
    int score = 100;
    if (name.contains('TOP')) score -= 30;
    if (name.contains('RAPIDO')) score -= 25;
    if (name.contains('VIDHIDE')) score -= 20;
    if (name.contains('STREAMWISH')) score -= 15;
    if (url.contains('.m3u8')) score -= 10;
    if (url.contains('.mp4')) score -= 6;
    if (name.contains('LATINO')) score -= 4;
    return score;
  }

  List<Map<String, dynamic>> _dedupeServers(List<Map<String, dynamic>> servers) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final raw in servers) {
      final normalized = _normalizeServer(raw);
      final url = (normalized['url'] as String).trim();
      if (url.isEmpty) continue;
      final key = url.toLowerCase();
      if (seen.add(key)) {
        out.add(normalized);
      }
    }
    return out;
  }

  Map<String, dynamic> _normalizeServer(dynamic raw) {
    final item = raw is Map ? raw : <String, dynamic>{};
    final url = item['url']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'SERVIDOR';
    final headersRaw = item['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      headersRaw.forEach((key, value) {
        if (key != null && value != null) {
          headers[key.toString()] = value.toString();
        }
      });
    }
    return {
      'name': name,
      'url': url,
      'headers': headers,
    };
  }
}

