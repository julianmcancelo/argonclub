import 'dart:ui';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../services/server_memory.dart';
import '../services/watch_history.dart';
import '../services/watch_party_prefs.dart';
import '../services/watch_party_service.dart';
import 'video_player_screen.dart';
import 'watch_party_lobby_screen.dart';
import '../widgets/tv_focusable_item.dart';

class DetailsScreen extends StatefulWidget {
  final dynamic itemData;
  final String type;
  final String id;

  const DetailsScreen({
    Key? key,
    required this.itemData,
    required this.type,
    required this.id,
  }) : super(key: key);

  @override
  _DetailsScreenState createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen>
    with TickerProviderStateMixin {
  String _accentName = 'Mono';
  bool _atmosphere = false;
  late AnimationController _auroraController;

  Color get currentAccentColor {
    switch (_accentName) {
      case 'Arena':
        return const Color(0xFFF2C078);
      case 'Niebla':
        return const Color(0xFFB7D8EE);
      case 'Mono':
      default:
        return _crimsonSoft;
    }
  }

  Color get colorBrandA => currentAccentColor;
  Color get colorBrandB => _accentName == 'Mono' ? _fire : currentAccentColor;

  Widget _buildAuroraBackground() {
    if (!_atmosphere) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _auroraController,
      builder: (context, child) {
        final val = _auroraController.value;
        final dx1 = 50.0 * val;
        final dy1 = 30.0 * (1.0 - val);
        final dx2 = -40.0 * val;
        final dy2 = 40.0 * val;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -260 + dy1,
              right: -140 + dx1,
              child: Container(
                width: 800,
                height: 800,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      currentAccentColor.withOpacity(0.08),
                      currentAccentColor.withOpacity(0.02),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -200 + dy2,
              left: -200 + dx2,
              child: Container(
                width: 700,
                height: 700,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      currentAccentColor.withOpacity(0.06),
                      currentAccentColor.withOpacity(0.01),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadTweakPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _accentName = prefs.getString('argon_tweak_accent') ?? 'Mono';
          _atmosphere = prefs.getBool('argon_tweak_atmosphere') ?? false;
        });
      }
    } catch (_) {}
  }

  final ApiClient _apiClient = ApiClient();
  static const Color _bg = Color(0xFF060606);
  static const Color _surface = Color(0xCC17171A);
  static const Color _surfaceSoft = Color(0xB3131316);
  static const Color _line = Color(0x22FFFFFF);
  static const Color _lineStrong = Color(0x44FFFFFF);
  static const Color _ink = Color(0xFFF4F1EA);
  static const Color _inkMuted = Color(0xFFD2CDC4);
  static const Color _muted = Color(0xFF8E877D);
  static const Color _crimson = Color(0xFFE63946);
  static const Color _crimsonSoft = Color(0xFFFF6B6B);
  static const Color _fire = Color(0xFFF97316);
  bool _isLoading = true;
  dynamic _details;

  // Servers list after background parsing
  List<Map<String, dynamic>> _resolvedServers = [];
  bool _isResolvingServers = false;

  // For TV Series
  List<dynamic> _seasons = [];
  dynamic _selectedSeason;

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
    _loadTweakPreferences();
    _fetchDetails();
  }

  @override
  void dispose() {
    _auroraController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    try {
      final details = await _apiClient.getSingleDetails(widget.type, widget.id);
      setState(() {
        _details = details;

        // Parse seasons if TV Series
        if (widget.type == 'tvseries' &&
            _details['season'] != null &&
            _details['season'] is List) {
          _seasons = _details['season'];
          if (_seasons.isNotEmpty) {
            _selectedSeason = _seasons[0];
          }
        }
      });

      setState(() {
        _isLoading = false;
      });

      // Parse and merge Multiple Rápido servers in background asynchronously
      _resolveAllServers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String? _getTmdbId() {
    final candidates = <dynamic>[
      _details?['tmdb_id'],
      _details?['tmdb'],
      _details?['tmdbId'],
      _details?['id_tmdb'],
      widget.itemData['tmdb_id'],
      widget.itemData['tmdb'],
      widget.itemData['tmdbId'],
      widget.itemData['id_tmdb'],
    ];
    for (final raw in candidates) {
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      final onlyDigits = RegExp(r'(\d{1,10})').firstMatch(s)?.group(1);
      if (onlyDigits != null && onlyDigits.isNotEmpty) return onlyDigits;
    }
    // Last fallback: scan key names containing "tmdb"
    if (_details is Map) {
      for (final e in (_details as Map).entries) {
        final k = e.key.toString().toLowerCase();
        if (!k.contains('tmdb')) continue;
        final v = e.value?.toString().trim() ?? '';
        if (v.isEmpty) continue;
        final onlyDigits = RegExp(r'(\d{1,10})').firstMatch(v)?.group(1);
        if (onlyDigits != null && onlyDigits.isNotEmpty) return onlyDigits;
      }
    }
    return null;
  }

  String? _getImdbId() {
    final raw =
        _details?['imdb_id'] ??
        _details?['imdb'] ??
        widget.itemData['imdb_id'] ??
        widget.itemData['imdb'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final ttMatch = RegExp(r'(tt\d{5,10})', caseSensitive: false).firstMatch(s);
    if (ttMatch != null) {
      return ttMatch.group(1)!.toLowerCase();
    }
    final digits = RegExp(r'(\d{5,10})').firstMatch(s)?.group(1);
    if (digits != null) {
      return 'tt$digits';
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _resolveVimeus(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        ApiClient.wrapUrl(url),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://vimeus.com/',
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final html = response.data ?? '';
      final dataRegex = RegExp(
        r'<script type="text\/json" id="data">([\s\S]*?)<\/script>',
      );
      final match = dataRegex.firstMatch(html);
      if (match == null) return [];

      final jsonStr = match.group(1)?.trim() ?? '';
      if (jsonStr.isEmpty) return [];

      final data = jsonDecode(jsonStr);
      if (data is Map && data['embeds'] is List) {
        final out = <Map<String, dynamic>>[];
        final embeds = data['embeds'] as List;
        for (var embed in embeds) {
          if (embed is Map && embed['url'] != null) {
            final embedUrl = embed['url'].toString();
            final serverName = (embed['server'] ?? 'Online')
                .toString()
                .toUpperCase();
            final lang = (embed['lang'] ?? 'Latino').toString().toUpperCase();
            final quality = (embed['quality'] ?? 'HD').toString().toUpperCase();

            out.add({
              'name': 'VIMEUS ($serverName - $lang $quality)',
              'url': embedUrl,
              'headers': {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://vimeus.com/',
              },
              'serverType': _classifyServerType(embedUrl, null),
            });
          }
        }
        return out;
      }

      // Fallback: direct stream urls present in HTML script blobs
      final htmlUrls = <String>{};
      final re = RegExp(r'''https?:\\/\\/[^\s"'<>\\]+''', caseSensitive: false);
      for (final m in re.allMatches(html)) {
        final rawUrl = m.group(0);
        if (rawUrl == null) continue;
        final clean = rawUrl.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
        if (clean.contains('.m3u8') ||
            clean.contains('.mp4') ||
            clean.contains('/playlist')) {
          htmlUrls.add(clean);
        }
      }
      if (htmlUrls.isNotEmpty) {
        return htmlUrls
            .map(
              (u) => {
                'name': 'VIMEUS (AUTO)',
                'url': u,
                'headers': {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Referer': 'https://vimeus.com/',
                },
                'serverType': _classifyServerType(u, null),
              },
            )
            .toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const [
          {'is404': true},
        ];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<String?> _lookupVimeusTmdbByImdb({
    required String imdbId,
    required bool isSeries,
    required bool isAnime,
    String? titleHint,
  }) async {
    final cleanImdb = imdbId.trim().toLowerCase();
    if (cleanImdb.isEmpty) return null;

    final dio = Dio();
    final endpoints = <String>[
      if (isSeries && isAnime) 'animes',
      if (isSeries) 'series',
      if (!isSeries) 'movies',
      // Safety fallbacks
      if (isSeries && !isAnime) 'animes',
      if (!isSeries) 'series',
    ];

    for (final endpoint in endpoints) {
      try {
        final res = await dio.get(
          ApiClient.wrapUrl('https://vimeus.com/api/listing/$endpoint'),
          queryParameters: {'page': 1, 'q': cleanImdb},
          options: Options(
            headers: {
              'X-API-Key': ApiClient.vimeusApiKey,
              'User-Agent': 'Mozilla/5.0',
            },
            sendTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
          ),
        );

        final data = res.data;
        final result =
            (data is Map &&
                data['data'] is Map &&
                data['data']['result'] is List)
            ? (data['data']['result'] as List)
            : const <dynamic>[];
        if (result.isEmpty) continue;

        Map? exact;
        for (final row in result) {
          if (row is! Map) continue;
          final imdb = (row['imdb_id'] ?? '').toString().toLowerCase();
          if (imdb == cleanImdb) {
            exact = row;
            break;
          }
        }

        Map? picked = exact;
        if (picked == null &&
            titleHint != null &&
            titleHint.trim().isNotEmpty) {
          final t = titleHint.toLowerCase();
          for (final row in result) {
            if (row is! Map) continue;
            final title = (row['title'] ?? '').toString().toLowerCase();
            if (title.contains(t) || t.contains(title)) {
              picked = row;
              break;
            }
          }
        }
        picked ??= result.first is Map ? result.first as Map : null;

        final tmdb = picked?['tmdb_id']?.toString().trim() ?? '';
        if (tmdb.isNotEmpty) return tmdb;
      } catch (_) {
        // Keep non-blocking
      }
    }

    return null;
  }

  Future<String?> _lookupVimeusTmdbByTitle({
    required String title,
    required bool isSeries,
    required bool isAnime,
  }) async {
    final q = title.trim();
    if (q.isEmpty) return null;

    final dio = Dio();
    final endpoint = isSeries ? (isAnime ? 'animes' : 'series') : 'movies';
    try {
      final res = await dio.get(
        ApiClient.wrapUrl('https://vimeus.com/api/listing/$endpoint'),
        queryParameters: {'page': 1, 'q': q},
        options: Options(
          headers: {
            'X-API-Key': ApiClient.vimeusApiKey,
            'User-Agent': 'Mozilla/5.0',
          },
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final data = res.data;
      final result =
          (data is Map && data['data'] is Map && data['data']['result'] is List)
          ? (data['data']['result'] as List)
          : const <dynamic>[];
      if (result.isEmpty) return null;

      Map? best;
      final qLower = q.toLowerCase();
      for (final row in result) {
        if (row is! Map) continue;
        final t = (row['title'] ?? '').toString().toLowerCase();
        if (t == qLower || t.contains(qLower) || qLower.contains(t)) {
          best = row;
          break;
        }
      }
      best ??= result.first is Map ? result.first as Map : null;
      final tmdb = best?['tmdb_id']?.toString().trim() ?? '';
      if (tmdb.isNotEmpty) return tmdb;
    } catch (_) {
      // Non-blocking
    }
    return null;
  }

  String? _buildVimeusFallbackUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!host.contains('vimeus.com')) return null;
    if (!uri.path.startsWith('/e/')) return null;

    final qp = Map<String, String>.from(uri.queryParameters);
    final hasImdb = qp.containsKey('imdb') && (qp['imdb']?.isNotEmpty ?? false);
    final hasTmdb = qp.containsKey('tmdb') && (qp['tmdb']?.isNotEmpty ?? false);
    final imdbId = _getImdbId();
    final tmdbId = _getTmdbId();

    if (hasImdb && tmdbId != null) {
      qp.remove('imdb');
      qp['tmdb'] = tmdbId;
      return uri.replace(queryParameters: qp).toString();
    }

    if (hasTmdb && imdbId != null) {
      qp.remove('tmdb');
      qp['imdb'] = imdbId;
      return uri.replace(queryParameters: qp).toString();
    }

    return null;
  }

  // Resolves the Multiple Rápido HTML portal page in second plane to extract nested video servers
  Future<List<Map<String, dynamic>>> _resolveMultipleRapido(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        ApiClient.wrapUrl(url),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 9; G011A Build/PI) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/68.0.3440.70 Mobile Safari/537.36 buscari/53',
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

      // Match div elements that represent server cards
      final divRegex = RegExp(
        r'<div\b[^>]*class="[^"]*server-card[^"]*"[^>]*>',
        caseSensitive: false,
      );
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
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://server.bixplay.online/',
                'Origin': 'https://server.bixplay.online',
              },
            });
          }
        }
      }

      // Fallback matching
      if (out.isEmpty) {
        final fallbackRegex = RegExp(
          r'data-link="([^"]+)"[^>]*data-name="([^"]+)"',
          caseSensitive: false,
        );
        for (final match in fallbackRegex.allMatches(html)) {
          final link = match.group(1) ?? '';
          final name = match.group(2) ?? 'Servidor';
          if (link.isNotEmpty) {
            out.add({
              'name': '${name.toUpperCase()} (RÁPIDO)',
              'url': link,
              'headers': {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://server.bixplay.online/',
                'Origin': 'https://server.bixplay.online',
              },
            });
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _resolveAllServers() async {
    if (widget.type == 'tvseries') return; // Handled per-episode

    setState(() {
      _isResolvingServers = true;
    });

    List<Map<String, dynamic>> rawServers = [];
    if (widget.type == 'live') {
      // Live TV: use stream_url directly with header enrichment
      final url =
          _details?['stream_url']?.toString() ??
          widget.itemData['stream_url']?.toString() ??
          '';
      if (url.isNotEmpty) {
        final baseHeaders = _extractHeaders(_details ?? widget.itemData);
        final enrichedHeaders = _enrichHeaders(url, baseHeaders);
        final serverType = _classifyServerType(
          url,
          _details?['type']?.toString() ?? _details?['videoType']?.toString(),
        );
        rawServers.add({
          'name': 'DIRECTO',
          'url': url,
          'headers': enrichedHeaders,
          'serverType': serverType,
        });
      }
      // Check if there are additional streams in 'videos' array for live channels
      if (_details?['videos'] != null && _details?['videos'] is List) {
        for (var vid in (_details?['videos'] as List)) {
          final url =
              vid['file_url']?.toString() ??
              vid['stream_url']?.toString() ??
              '';
          final label =
              vid['label']?.toString() ?? vid['name']?.toString() ?? 'CANAL';
          if (url.isNotEmpty) {
            final baseHeaders = _extractHeaders(vid);
            final enrichedHeaders = _enrichHeaders(url, baseHeaders);
            final serverType = _classifyServerType(
              url,
              vid['videoType']?.toString() ?? vid['type']?.toString(),
            );
            rawServers.add({
              'name': label.toUpperCase(),
              'url': url,
              'headers': enrichedHeaders,
              'serverType': serverType,
            });
          }
        }
      }
    } else if (_details?['videos'] != null && _details?['videos'] is List) {
      for (var vid in _details?['videos']) {
        final url = vid['file_url']?.toString() ?? '';
        final label = vid['label']?.toString() ?? 'SERVIDOR';
        if (url.isNotEmpty) {
          final baseHeaders = _extractHeaders(vid);
          final enrichedHeaders = _enrichHeaders(url, baseHeaders);
          final serverType = _classifyServerType(
            url,
            vid['videoType']?.toString() ?? vid['type']?.toString(),
          );
          rawServers.add({
            'name': label.toUpperCase(),
            'url': url,
            'headers': enrichedHeaders,
            'serverType': serverType,
          });
        }
      }
    }

    // Inject VIMEUS server using TMDB and IMDB ID
    String? tmdbId = _getTmdbId();
    final imdbId = _getImdbId();
    final titleHint =
        (_details?['title'] ?? widget.itemData['title'])?.toString() ?? '';
    if (tmdbId == null && imdbId != null) {
      tmdbId = await _lookupVimeusTmdbByImdb(
        imdbId: imdbId,
        isSeries: false,
        isAnime: false,
        titleHint: titleHint.isEmpty ? null : titleHint,
      );
    }
    if (tmdbId == null && titleHint.isNotEmpty) {
      tmdbId = await _lookupVimeusTmdbByTitle(
        title: titleHint,
        isSeries: false,
        isAnime: false,
      );
    }
    if (widget.type == 'movie' || widget.type == 'movies') {
      if (tmdbId != null) {
        rawServers.add({
          'name': 'VIMEUS (TMDb)',
          'url':
              'https://vimeus.com/e/movie?tmdb=$tmdbId&view_key=${ApiClient.vimeusViewKey}',
          'headers': {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://vimeus.com/',
          },
          'serverType': 'embed',
        });
      }
      if (imdbId != null) {
        rawServers.add({
          'name': 'VIMEUS (IMDb)',
          'url':
              'https://vimeus.com/e/movie?imdb=$imdbId&view_key=${ApiClient.vimeusViewKey}',
          'headers': {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://vimeus.com/',
          },
          'serverType': 'embed',
        });
      }
    }

    // Decompress / Flatten Multiple Rápido portal server choices in background
    final finalizedRaw = await _resolveAndFinalizeServers(rawServers);
    final finalized = await _applyRememberedPriority(
      finalizedRaw,
      _moviePlaybackKey(),
    );

    setState(() {
      _resolvedServers = finalized;
      _isResolvingServers = false;
    });
  }

  bool _isMultiplePortalServer(Map<String, dynamic> server) {
    final url = server['url']?.toString().toLowerCase() ?? '';
    final label = server['name']?.toString().toUpperCase() ?? '';
    return url.contains('server.bixplay.online/server-nuevo-v2') ||
        label.contains('MULTIPLE');
  }

  int _serverPriority(Map<String, dynamic> server) {
    final name = server['name']?.toString().toUpperCase() ?? '';
    final url = server['url']?.toString().toLowerCase() ?? '';
    int score = 100;
    if (name.contains('VIMEUS (TMDB)')) score -= 40;
    if (name.contains('VIMEUS')) score -= 22;
    if (name.contains('TOP')) score -= 30;
    if (name.contains('RAPIDO')) score -= 25;
    if (name.contains('VIDHIDE')) score -= 20;
    if (name.contains('STREAMWISH')) score -= 15;
    if (url.contains('.m3u8')) score -= 10;
    if (url.contains('.mp4')) score -= 6;
    if (name.contains('LATINO')) score -= 4;
    return score;
  }

  String _moviePlaybackKey() {
    return '${widget.type}:${widget.id}';
  }

  String _episodePlaybackKey(dynamic episode) {
    final epId = episode['episodes_id']?.toString();
    if (epId != null && epId.isNotEmpty) {
      return 'tvseries:${widget.id}:ep:$epId';
    }
    final epName = episode['episodes_name']?.toString() ?? 'unknown';
    return 'tvseries:${widget.id}:name:${epName.toLowerCase()}';
  }

  Future<List<Map<String, dynamic>>> _applyRememberedPriority(
    List<Map<String, dynamic>> servers,
    String playbackKey,
  ) async {
    if (servers.isEmpty) return servers;
    final rememberedUrl = await ServerMemory.getLastWorkingServerUrl(
      playbackKey,
    );
    if (rememberedUrl == null || rememberedUrl.isEmpty) return servers;
    final idx = servers.indexWhere(
      (s) =>
          (s['url']?.toString() ?? '').toLowerCase() ==
          rememberedUrl.toLowerCase(),
    );
    if (idx <= 0) return servers;

    return [servers[idx], ...servers.take(idx), ...servers.skip(idx + 1)];
  }

  String _serverHealthTag(Map<String, dynamic> server) {
    final score = _serverPriority(server);
    if (score <= 70) return 'ESTABLE';
    if (score <= 85) return 'RAPIDO';
    return 'COMPATIBLE';
  }

  List<Map<String, dynamic>> _dedupeServers(
    List<Map<String, dynamic>> servers,
  ) {
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

  Future<List<Map<String, dynamic>>> _resolveAndFinalizeServers(
    List<Map<String, dynamic>> rawServers,
  ) async {
    final expanded = <Map<String, dynamic>>[];

    for (final raw in rawServers) {
      final normalized = _normalizeServer(raw);
      final url = normalized['url'] as String;
      if (url.isEmpty) continue;
      if (_isMultiplePortalServer(normalized)) {
        final nested = await _resolveMultipleRapido(url);
        if (nested.isNotEmpty) {
          expanded.addAll(nested.map(_normalizeServer));
          continue;
        }
      } else if (url.contains('vimeus.com')) {
        final nested = await _resolveVimeus(url);
        if (nested.isNotEmpty && nested.first['is404'] != true) {
          expanded.addAll(nested.map(_normalizeServer));
        } else {
          final fallbackUrl = _buildVimeusFallbackUrl(url);
          if (fallbackUrl != null && fallbackUrl != url) {
            final fallbackNested = await _resolveVimeus(fallbackUrl);
            if (fallbackNested.isNotEmpty &&
                fallbackNested.first['is404'] != true) {
              expanded.addAll(fallbackNested.map(_normalizeServer));
              continue;
            }
            // Keep TMDb fallback candidate visible for runtime resolution.
            final fallbackCandidate = Map<String, dynamic>.from(normalized);
            fallbackCandidate['url'] = fallbackUrl;
            final name = (fallbackCandidate['name']?.toString() ?? 'VIMEUS')
                .toUpperCase();
            if (!name.contains('TMDB')) {
              fallbackCandidate['name'] = 'VIMEUS (TMDb)';
            }
            expanded.add(fallbackCandidate);
            continue;
          }
          // Keep original candidate visible even if vimeus currently has no match.
          // Runtime player now fails fast on HTTP 404 and auto-switches server.
          expanded.add(normalized);
          continue;
        }
        continue;
      }
      expanded.add(normalized);
    }

    final deduped = _dedupeServers(expanded);
    deduped.sort((a, b) => _serverPriority(a).compareTo(_serverPriority(b)));
    return deduped;
  }

  // TV Series Episode server selector popup (shows premium server cards layout in a beautiful floating dialog)
  void _showServerDialog(
    List<Map<String, dynamic>> servers,
    String episodeTitle,
    bool isTV, {
    List<dynamic>? episodesList,
    int? currentEpisodeIndex,
    String playbackKey = '',
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isTV ? 120 : 20,
            vertical: isTV ? 60 : 30,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF06060A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _line, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.85),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        episodeTitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorBrandA.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorBrandA.withOpacity(0.4)),
                  ),
                  child: Text(
                    '${servers.length} opciones disponibles',
                    style: const TextStyle(
                      color: Color(0xFFC0A6FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: servers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final s = entry.value;
                        return _buildServerCard(
                          server: s,
                          index: idx,
                          isTV: isTV,
                          onTap: () {
                            Navigator.pop(context);
                            _showPlaybackChoiceDialog(
                              servers,
                              idx,
                              episodesList: episodesList,
                              currentEpisodeIndex: currentEpisodeIndex,
                              playbackKey: playbackKey,
                            );
                          },
                          onLongPress: () {
                            Navigator.pop(context);
                            _playVideoFromServerList(
                              servers,
                              idx,
                              episodesList: episodesList,
                              currentEpisodeIndex: currentEpisodeIndex,
                              playbackKey: playbackKey,
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    // Preserve serverType metadata so VideoPlayerScreen knows how to handle it
    final serverType = item['serverType']?.toString() ?? '';
    return {
      'name': name,
      'url': url,
      'headers': headers,
      if (serverType.isNotEmpty) 'serverType': serverType,
    };
  }

  Future<void> _playVideoFromServerList(
    List<Map<String, dynamic>> servers,
    int selectedIndex, {
    List<dynamic>? episodesList,
    int? currentEpisodeIndex,
    String playbackKey = '',
    WatchPartySession? partySession,
  }) async {
    if (servers.isEmpty || selectedIndex < 0 || selectedIndex >= servers.length)
      return;

    final selected = _normalizeServer(servers[selectedIndex]);
    if ((selected['url'] as String).isEmpty) return;

    final prioritized = <Map<String, dynamic>>[selected];
    for (int i = 0; i < servers.length; i++) {
      if (i == selectedIndex) continue;
      final normalized = _normalizeServer(servers[i]);
      if ((normalized['url'] as String).isNotEmpty) {
        prioritized.add(normalized);
      }
    }

    final finalQueue = playbackKey.isNotEmpty
        ? await _applyRememberedPriority(prioritized, playbackKey)
        : prioritized;

    final first = finalQueue.first;
    final url = first['url'] as String;
    final headers = first['headers'] as Map<String, String>;
    final isDirect = _isDirectStreamUrl(url);
    final mediaTitle =
        widget.itemData['title'] ?? widget.itemData['tv_name'] ?? 'Contenido';
    final posterUrl =
        (widget.itemData['tmdb_poster_url'] ??
                widget.itemData['poster_url'] ??
                widget.itemData['thumbnail_url'] ??
                widget.itemData['image_url'] ??
                '')
            .toString();
    final resumeSeconds = playbackKey.isNotEmpty
        ? await WatchHistoryService.getResumeSeconds(playbackKey)
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: url,
          isDirect: isDirect,
          headers: headers,
          serverQueue: finalQueue,
          episodesList: episodesList,
          currentEpisodeIndex: currentEpisodeIndex,
          mediaTitle: mediaTitle,
          mediaType: widget.type,
          mediaId: widget.id,
          mediaPosterUrl: posterUrl,
          playbackKey: playbackKey,
          startPositionSeconds: resumeSeconds ?? 0,
          initialWatchPartySession: partySession,
        ),
      ),
    );
  }

  Future<void> _showPlaybackChoiceDialog(
    List<Map<String, dynamic>> servers,
    int selectedIndex, {
    List<dynamic>? episodesList,
    int? currentEpisodeIndex,
    String playbackKey = '',
  }) async {
    await _playVideoFromServerList(
      servers,
      selectedIndex,
      episodesList: episodesList,
      currentEpisodeIndex: currentEpisodeIndex,
      playbackKey: playbackKey,
    );
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

  Future<WatchPartySession?> _showWatchPartySetupDialog() async {
    final roomController = TextEditingController();
    bool createMode = true;
    String info = '';
    String generatedRoom = _generateRoomCode();
    final displayName = await WatchPartyPrefs.getDisplayName();

    return showDialog<WatchPartySession>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _surface,
              title: const Text(
                'Ver en grupo',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setDialogState(() {
                                createMode = true;
                                generatedRoom = _generateRoomCode();
                                info = '';
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: createMode
                                          ? Colors.white
                                          : Colors.white24,
                                      width: createMode ? 3 : 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Crear sala',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: createMode
                                        ? Colors.white
                                        : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setDialogState(() {
                                createMode = false;
                                info = '';
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: !createMode
                                          ? Colors.white
                                          : Colors.white24,
                                      width: !createMode ? 3 : 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Unirse',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !createMode
                                        ? Colors.white
                                        : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Nombre configurado: $displayName',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Room code input
                    if (createMode) ...[
                      const Text(
                        'Codigo listo para compartir',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        generatedRoom,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Se copia al portapapeles al crear la sala.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ] else
                      TextField(
                        controller: roomController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'Código de sala',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Ej: AB12CD',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          counterStyle: const TextStyle(color: Colors.white38),
                        ),
                      ),

                    // Info message
                    if (info.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          info,
                          style: TextStyle(
                            color:
                                info.contains('Error') ||
                                    info.contains('invalido')
                                ? Colors.redAccent
                                : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final room = createMode
                        ? generatedRoom
                        : _normalizeRoomCode(roomController.text);

                    if (!createMode && room.length < 4) {
                      setDialogState(() {
                        info = 'Código inválido. Debe tener 4+ caracteres.';
                      });
                      return;
                    }

                    if (createMode) {
                      await Clipboard.setData(
                        ClipboardData(
                          text: 'Mira conmigo en Zuper. Sala: $room',
                        ),
                      );
                      setDialogState(() {
                        info = 'Codigo copiado al portapapeles';
                      });
                    }

                    await Future.delayed(const Duration(milliseconds: 300));
                    if (!context.mounted) return;

                    Navigator.pop(
                      context,
                      WatchPartySession(
                        roomId: room,
                        peerName: displayName,
                        isHost: createMode,
                      ),
                    );
                  },
                  child: Text(
                    createMode ? 'Crear' : 'Unirse',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, String> _extractHeaders(dynamic item) {
    Map<String, String> headers = {};
    // Original APK has header1..header5 pairs (zw.java model)
    // We iterate up to 8 for forward compatibility
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

  /// Classifies the server type from a URL and optional videoType field.
  /// Mirrors the lIlI() static method from TvDetailsActivity.java
  String _classifyServerType(String url, String? videoType) {
    final lower = url.toLowerCase();
    // If no URL, use provided videoType or default to 'embed'
    if (url.isEmpty) {
      return (videoType != null && videoType.isNotEmpty) ? videoType : 'embed';
    }
    // Explicit embed-type sites that need WebView
    if (lower.contains('streamwish') ||
        lower.contains('vidhide') ||
        lower.contains('filemoon') ||
        lower.contains('voe.sx') ||
        lower.contains('dood')) {
      return 'custom';
    }
    // Embed patterns requiring WebView
    if (lower.contains('yourupload') ||
        lower.contains('upstream') ||
        lower.contains('vimeo.com') ||
        lower.contains('vimeus.com') ||
        lower.contains('vimeus') ||
        lower.contains('drive.google.com') ||
        lower.contains('youtube.com') ||
        lower.contains('m3u8embed') ||
        lower.contains('repro2.php') ||
        lower.contains('plustream') ||
        lower.contains('pelisplushdserver')) {
      return 'embed';
    }
    // Direct stream URLs
    if (lower.contains('.m3u8')) return 'hls';
    if (lower.contains('.mp4')) return 'mp4';
    // Fallback to provided videoType or 'embed'
    if (videoType != null && videoType.isNotEmpty) return videoType;
    return 'embed';
  }

  /// Enriches headers for specific server types that need special headers.
  /// Mirrors the header injection in Il0()/l0I() from TvDetailsActivity.java
  Map<String, String> _enrichHeaders(String url, Map<String, String> base) {
    final headers = Map<String, String>.from(base);
    final lower = url.toLowerCase();

    // filemoon, streamwish, voe.sx — inject Origin, Referer, User-Agent
    if (lower.contains('filemoon') ||
        lower.contains('streamwish') ||
        lower.contains('voe.sx')) {
      headers.putIfAbsent('Origin', () => url);
      headers.putIfAbsent('Referer', () => url);
      headers.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      );
    }

    // doodstream variants — same treatment
    final doodPattern = RegExp(
      r'(?://|\.)dood(?:stream)?\.(?:com|watch|to|so|la|ws|sh|li)',
      caseSensitive: false,
    );
    if (doodPattern.hasMatch(url)) {
      headers.putIfAbsent('Origin', () => url);
      headers.putIfAbsent('Referer', () => url);
      headers.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      );
    }

    // plustream — needs streamsito.com referer
    if (lower.contains('plustream')) {
      headers['Referer'] = 'https://streamsito.com/';
    }

    // yourupload — needs the stream URL as Referer (mirroring original)
    if (lower.contains('yourupload')) {
      headers.putIfAbsent('Referer', () => url);
    }

    // Default fallback User-Agent if none set
    headers.putIfAbsent(
      'User-Agent',
      () =>
          'Mozilla/5.0 (Linux; Android 10; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );

    return headers;
  }

  bool _isDirectStreamUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm');
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: colorBrandA),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePlayEpisode(dynamic episode) async {
    final isTV = _isTV(context);
    final episodes =
        _selectedSeason != null && _selectedSeason['episodes'] != null
        ? (_selectedSeason['episodes'] as List)
        : <dynamic>[];
    final episodeIndex = episodes.indexOf(episode);
    final playbackKey = _episodePlaybackKey(episode);

    // Resolving episode servers
    List<Map<String, dynamic>> servers = [];

    final directUrl = episode['file_url']?.toString() ?? '';
    final directLabel = episode['label']?.toString() ?? 'SERVIDOR 1';
    if (directUrl.isNotEmpty) {
      final baseHeaders = _extractHeaders(episode);
      final enrichedHeaders = _enrichHeaders(directUrl, baseHeaders);
      final serverType = _classifyServerType(
        directUrl,
        episode['videoType']?.toString() ?? episode['type']?.toString(),
      );
      servers.add({
        'name': directLabel.toUpperCase(),
        'url': directUrl,
        'headers': enrichedHeaders,
        'serverType': serverType,
      });
    }

    if (episode['videos'] != null && episode['videos'] is List) {
      for (var vid in episode['videos']) {
        final url = vid['file_url']?.toString() ?? '';
        final label = vid['label']?.toString() ?? 'SERVIDOR';
        if (url.isNotEmpty) {
          final baseHeaders = _extractHeaders(vid);
          final enrichedHeaders = _enrichHeaders(url, baseHeaders);
          final serverType = _classifyServerType(
            url,
            vid['videoType']?.toString() ?? vid['type']?.toString(),
          );
          servers.add({
            'name': label.toUpperCase(),
            'url': url,
            'headers': enrichedHeaders,
            'serverType': serverType,
          });
        }
      }
    }

    // Inject VIMEUS server using TMDB and IMDB ID
    final isAnime =
        widget.itemData['genre']?.toString().toLowerCase().contains('anime') ==
            true ||
        _details?['genre']?.toString().toLowerCase().contains('anime') == true;

    String? tmdbId = _getTmdbId();
    final imdbId = _getImdbId();
    final titleHint =
        (_details?['title'] ??
                widget.itemData['tv_name'] ??
                widget.itemData['title'])
            ?.toString() ??
        '';
    if (tmdbId == null && imdbId != null) {
      tmdbId = await _lookupVimeusTmdbByImdb(
        imdbId: imdbId,
        isSeries: true,
        isAnime: isAnime,
        titleHint: titleHint.isEmpty ? null : titleHint,
      );
    }
    if (tmdbId == null && titleHint.isNotEmpty) {
      tmdbId = await _lookupVimeusTmdbByTitle(
        title: titleHint,
        isSeries: true,
        isAnime: isAnime,
      );
    }
    if (tmdbId != null || imdbId != null) {
      // Parse season and episode number
      int seasonNum = 1;
      if (_selectedSeason != null) {
        final rawSe =
            _selectedSeason['season_number'] ?? _selectedSeason['season'];
        if (rawSe != null) {
          seasonNum = int.tryParse(rawSe.toString()) ?? 1;
        } else {
          final name = _selectedSeason['seasons_name']?.toString() ?? '';
          final match = RegExp(r'\d+').firstMatch(name);
          if (match != null) {
            seasonNum = int.tryParse(match.group(0)!) ?? 1;
          } else {
            final idx = _seasons.indexOf(_selectedSeason);
            if (idx != -1) seasonNum = idx + 1;
          }
        }
      }

      int episodeNum = 1;
      final rawEp = episode['episode_number'] ?? episode['episode'];
      if (rawEp != null) {
        episodeNum = int.tryParse(rawEp.toString()) ?? 1;
      } else {
        final name = episode['episodes_name']?.toString() ?? '';
        final match = RegExp(r'\d+').firstMatch(name);
        if (match != null) {
          episodeNum = int.tryParse(match.group(0)!) ?? 1;
        } else {
          final idx = episodes.indexOf(episode);
          if (idx != -1) episodeNum = idx + 1;
        }
      }

      final endpoint = isAnime ? 'anime' : 'serie';

      if (tmdbId != null) {
        servers.add({
          'name': 'VIMEUS (TMDb)',
          'url':
              'https://vimeus.com/e/$endpoint?tmdb=$tmdbId&se=$seasonNum&ep=$episodeNum&view_key=${ApiClient.vimeusViewKey}',
          'headers': {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://vimeus.com/',
          },
          'serverType': 'embed',
        });
      }
      if (imdbId != null) {
        servers.add({
          'name': 'VIMEUS (IMDb)',
          'url':
              'https://vimeus.com/e/$endpoint?imdb=$imdbId&se=$seasonNum&ep=$episodeNum&view_key=${ApiClient.vimeusViewKey}',
          'headers': {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://vimeus.com/',
          },
          'serverType': 'embed',
        });
      }
    }

    // Show non-intrusive loading dialog
    _showLoadingDialog(context, 'Buscando servidores...');

    try {
      final finalizedRaw = await _resolveAndFinalizeServers(servers);
      final finalized = await _applyRememberedPriority(
        finalizedRaw,
        playbackKey,
      );
      if (!mounted) return;

      // Close the loading dialog
      Navigator.pop(context);

      if (finalized.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron servidores para este episodio.'),
          ),
        );
        return;
      }

      if (finalized.length == 1) {
        _showPlaybackChoiceDialog(
          finalized,
          0,
          episodesList: episodes,
          currentEpisodeIndex: episodeIndex,
          playbackKey: playbackKey,
        );
        return;
      }

      _showServerDialog(
        finalized,
        episode['episodes_name'] ?? 'Selecciona Servidor',
        isTV,
        episodesList: episodes,
        currentEpisodeIndex: episodeIndex,
        playbackKey: playbackKey,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al resolver: $e')));
      }
    }
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);
    final width = MediaQuery.of(context).size.width;
    final tvScale = isTV ? (width / 1920).clamp(0.82, 1.18) : 1.0;
    final title =
        widget.itemData['title'] ??
        widget.itemData['tv_name'] ??
        widget.itemData['channel_name'] ??
        'Detalles';
    final posterUrl =
        widget.itemData['poster_url'] ??
        widget.itemData['image_url'] ??
        widget.itemData['thumbnail_url'] ??
        widget.itemData['logo'] ??
        '';
    final description = _details != null
        ? (_details['description'] ??
              widget.itemData['description'] ??
              'Sin descripción.')
        : 'Cargando...';

    // Extracted Metadatas
    final rating =
        _details?['imdb_rating']?.toString() ??
        widget.itemData['imdb_rating']?.toString() ??
        '8.0';
    final release =
        _details?['release']?.toString() ??
        widget.itemData['release']?.toString() ??
        '2024';
    final runtime =
        _details?['runtime']?.toString() ??
        widget.itemData['runtime']?.toString() ??
        '120 min';

    List<String> genres = [];
    if (_details != null && _details['genre'] is List) {
      for (var g in _details['genre']) {
        if (g is Map && g.containsKey('name')) {
          genres.add(g['name'].toString());
        }
      }
    } else if (widget.itemData['genre'] != null) {
      final gStr = widget.itemData['genre'].toString();
      genres = gStr.split(',').map((e) => e.trim()).toList();
    }
    if (genres.isEmpty) {
      genres = ['Acción', 'Aventura'];
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildAuroraBackground(),
          // Background faint blurred movie poster (Cinematic overlay - Optimized for TV)
          if (posterUrl.isNotEmpty) ...[
            Opacity(
              opacity: 0.15,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: isTV ? 6.0 : 25.0,
                  sigmaY: isTV ? 6.0 : 25.0,
                ),
                child: CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: isTV ? 960 : 640,
                ),
              ),
            ),
          ],

          // Gradient fade on top of blurred poster
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _bg],
                stops: [0.1, 0.8],
              ),
            ),
          ),

          // Main layout content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTV ? 20.0 * tvScale : 16.0,
                    vertical: isTV ? 10.0 * tvScale : 8.0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: _ink,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ficha y reproduccion',
                        style: GoogleFonts.dmSans(
                          color: _inkMuted,
                          fontSize: isTV ? 18 * tvScale : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                // Body Contents
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(color: colorBrandA),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTV ? 24.0 * tvScale : 16.0,
                            vertical: isTV ? 14.0 * tvScale : 16.0,
                          ),
                          child: isTV
                              ? _buildLandscapeTVLayout(
                                  title,
                                  posterUrl,
                                  rating,
                                  release,
                                  runtime,
                                  genres,
                                  description,
                                )
                              : _buildPortraitMobileLayout(
                                  title,
                                  posterUrl,
                                  rating,
                                  release,
                                  runtime,
                                  genres,
                                  description,
                                ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TV LANDSCAPE LAYOUT ---
  Widget _buildLandscapeTVLayout(
    String title,
    String posterUrl,
    String rating,
    String release,
    String runtime,
    List<String> genres,
    String description,
  ) {
    final tvScale = _isTV(context)
        ? (MediaQuery.of(context).size.width / 1920).clamp(0.82, 1.18)
        : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(18 * tvScale),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_surface, _surfaceSoft, Colors.black.withOpacity(0.16)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _lineStrong),
            boxShadow: [
              BoxShadow(
                color: _crimson.withOpacity(0.14),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPosterWithRating(posterUrl, rating, true),
              SizedBox(width: 24 * tvScale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * tvScale,
                        vertical: 5 * tvScale,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_crimson, _fire],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.type == 'tvseries' ? 'SERIE' : 'PELÍCULA',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 11 * tvScale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    SizedBox(height: 10 * tvScale),
                    Text(
                      title,
                      style: GoogleFonts.bebasNeue(
                        color: _ink,
                        fontSize: 38 * tvScale,
                        height: 0.95,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 12 * tvScale),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaCapsule('★ $rating'),
                        _buildMetaCapsule(release),
                        _buildMetaCapsule(runtime),
                        ...genres
                            .take(3)
                            .map((g) => _buildMetaCapsule(g))
                            .toList(),
                      ],
                    ),
                    SizedBox(height: 16 * tvScale),
                    Text(
                      description,
                      style: GoogleFonts.dmSans(
                        color: _inkMuted,
                        fontSize: 15 * tvScale,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24 * tvScale),
        Divider(color: _lineStrong, thickness: 1.2),
        SizedBox(height: 18 * tvScale),

        // Bottom details section: Servers / Episodes grid
        if (widget.type == 'tvseries') ...[
          _buildTVSeriesSection(true),
        ] else ...[
          _buildMovieServersSection(true),
        ],
      ],
    );
  }

  // --- MOBILE PORTRAIT LAYOUT ---
  Widget _buildPortraitMobileLayout(
    String title,
    String posterUrl,
    String rating,
    String release,
    String runtime,
    List<String> genres,
    String description,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Details stacked vertically
        Center(child: _buildPosterWithRating(posterUrl, rating, false)),
        const SizedBox(height: 24),

        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Metadata Pills
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildMetaCapsule(release),
              _buildMetaCapsule(runtime),
              ...genres.map((g) => _buildMetaCapsule(g)).toList(),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          description,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        const Divider(color: Color(0xFF1F1F30), thickness: 1.5),
        const SizedBox(height: 20),

        // Bottom details section
        if (widget.type == 'tvseries') ...[
          _buildTVSeriesSection(false),
        ] else ...[
          _buildMovieServersSection(false),
        ],
      ],
    );
  }

  // Poster Image Widget with imdb star pill overlayed
  Widget _buildPosterWithRating(String posterUrl, String rating, bool isTV) {
    final tvScale = isTV
        ? (MediaQuery.of(context).size.width / 1920).clamp(0.82, 1.18)
        : 1.0;
    final posterWidth = isTV ? 180.0 * tvScale : 130.0;
    final posterHeight = isTV ? 270.0 * tvScale : 190.0;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    width: posterWidth,
                    height: posterHeight,
                    fit: BoxFit.cover,
                    memCacheWidth: isTV ? (posterWidth * 1.2).round() : 160,
                    errorWidget: (context, url, error) => Container(
                      width: posterWidth,
                      height: posterHeight,
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.movie,
                        color: Colors.white24,
                        size: 50,
                      ),
                    ),
                  )
                : Container(
                    width: posterWidth,
                    height: posterHeight,
                    color: Colors.grey[900],
                    child: const Icon(
                      Icons.movie,
                      color: Colors.white24,
                      size: 50,
                    ),
                  ),
          ),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFC107),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  rating,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFFFC107),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Metadata capsule
  Widget _buildMetaCapsule(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _lineStrong, width: 1.0),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // --- MOVIE SERVERS BOTTOM SECTION ---
  Widget _buildMovieServersSection(bool isTV) {
    final serverCount = _resolvedServers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SERVIDORES DISPONIBLES',
              style: GoogleFonts.bebasNeue(
                color: _ink,
                fontSize: isTV ? 28 : 20,
                letterSpacing: 1.0,
              ),
            ),
            if (!_isResolvingServers)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _lineStrong),
                ),
                child: Text(
                  '$serverCount opciones',
                  style: GoogleFonts.dmSans(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // Display Server Skeletons / Grid list
        if (_isResolvingServers) ...[
          if (isTV)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 16,
              childAspectRatio: 3.8,
              children: List.generate(4, (index) => _buildServerSkeleton()),
            )
          else
            Column(
              children: List.generate(3, (index) => _buildServerSkeleton()),
            ),
        ] else if (_resolvedServers.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                'No hay servidores disponibles!',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ] else ...[
          // Grid/List of real servers
          isTV
              ? GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _resolvedServers.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 3.5,
                  ),
                  itemBuilder: (context, index) {
                    final s = _resolvedServers[index];
                    return _buildServerCard(
                      server: s,
                      index: index,
                      isTV: true,
                      onTap: () => _showPlaybackChoiceDialog(
                        _resolvedServers,
                        index,
                        playbackKey: _moviePlaybackKey(),
                      ),
                      onLongPress: () => _playVideoFromServerList(
                        _resolvedServers,
                        index,
                        playbackKey: _moviePlaybackKey(),
                      ),
                    );
                  },
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _resolvedServers.length,
                  itemBuilder: (context, index) {
                    final s = _resolvedServers[index];
                    return _buildServerCard(
                      server: s,
                      index: index,
                      isTV: false,
                      onTap: () => _showPlaybackChoiceDialog(
                        _resolvedServers,
                        index,
                        playbackKey: _moviePlaybackKey(),
                      ),
                      onLongPress: () => _playVideoFromServerList(
                        _resolvedServers,
                        index,
                        playbackKey: _moviePlaybackKey(),
                      ),
                    );
                  },
                ),
        ],
      ],
    );
  }

  // --- TV SERIES BOTTOM SECTION ---
  Widget _buildTVSeriesSection(bool isTV) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TEMPORADAS',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: isTV ? 20 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_seasons.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line, width: 1.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<dynamic>(
                    value: _selectedSeason,
                    dropdownColor: const Color(0xFF0F0F18),
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: colorBrandA,
                    ),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    onChanged: (v) => setState(() => _selectedSeason = v),
                    items: _seasons.map<DropdownMenuItem<dynamic>>((s) {
                      return DropdownMenuItem<dynamic>(
                        value: s,
                        child: Text(s['seasons_name'] ?? 'Temporada'),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Skeletons
        if (_isResolvingServers) ...[
          Center(child: CircularProgressIndicator(color: colorBrandA)),
        ] else if (_selectedSeason != null &&
            _selectedSeason['episodes'] != null) ...[
          Text(
            'EPISODIOS',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          // Episodes list
          ...(_selectedSeason['episodes'] as List).map((episode) {
            return _buildEpisodeCard(episode, isTV);
          }).toList(),
        ] else ...[
          const Text(
            'No hay episodios disponibles.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ],
    );
  }

  // --- PREMIUM COMPONENT: SERVER HORIZONTAL SELECTOR CARD ---
  Widget _buildServerCard({
    required Map<String, dynamic> server,
    required int index,
    required bool isTV,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final serverName = server['name'] as String? ?? 'SERVIDOR';
    final isTop =
        serverName.contains('TOP') ||
        serverName.contains('RÁPIDO') ||
        index == 0;
    final healthTag = _serverHealthTag(server);

    return TvFocusableItem(
      autofocus: index == 0,
      onPressed: onTap,
      focusColor: _crimsonSoft,
      scaleOnFocus: 1.03,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_surfaceSoft, const Color(0xCC101013)],
            ),
          ),
          child: Row(
            children: [
              // Index Circle Badge
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _crimson.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Server Title and Status Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            serverName,
                            style: GoogleFonts.dmSans(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isTop) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_crimson, _fire],
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'TOP',
                              style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _lineStrong, width: 0.8),
                          ),
                          child: Text(
                            healthTag,
                            style: GoogleFonts.dmSans(
                              color: _inkMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: GoogleFonts.dmSans(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Purple Play Button Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_crimson, _fire]),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: _crimson.withOpacity(0.34),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Skeleton Loader for resolved servers loading state
  Widget _buildServerSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF1F1F30),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _line,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  // Episode focusable list card widget
  Widget _buildEpisodeCard(dynamic episode, bool isTV) {
    final epTitle = episode['episodes_name'] ?? 'Episodio';
    final epImage = episode['image_url'] ?? '';
    final epDesc = episode['episodes_description'] ?? '';

    return TvFocusableItem(
      onPressed: () => _handlePlayEpisode(episode),
      focusColor: _crimsonSoft,
      scaleOnFocus: 1.02,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF0F0F18)),
        child: ListTile(
          contentPadding: EdgeInsets.all(isTV ? 12 : 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: epImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: epImage,
                    width: isTV ? 140 : 90,
                    height: isTV ? 80 : 54,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        ((isTV ? 140 : 90) *
                                MediaQuery.of(context).devicePixelRatio)
                            .round(),
                    memCacheHeight:
                        ((isTV ? 80 : 54) *
                                MediaQuery.of(context).devicePixelRatio)
                            .round(),
                    errorWidget: (c, u, e) => const Icon(Icons.error),
                  )
                : Container(
                    width: isTV ? 140 : 90,
                    height: isTV ? 80 : 54,
                    color: Colors.grey[800],
                    child: const Icon(Icons.tv, color: Colors.white54),
                  ),
          ),
          title: Text(
            epTitle,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isTV ? 17 : 14,
            ),
          ),
          subtitle: epDesc.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    epDesc,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white54,
                      fontSize: isTV ? 14 : 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          trailing: Icon(
            Icons.play_circle_fill,
            color: Colors.white54,
            size: isTV ? 36 : 28,
          ),
        ),
      ),
    );
  }
}
