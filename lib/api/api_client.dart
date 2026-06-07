import 'package:dio/dio.dart';
import '../services/error_logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class ApiClient {
  static const String baseUrl = 'https://appnew2.bixplay.online/rest-api/v100/';
  static const String searchBaseUrl = 'https://appnew2.bixplay.online/api/';
  static const String apiKey = '1997c52cf132adc5ab840337fde468b8';
  static const String searchApiKey = '3uhb6okvkkxohc4zh4i7lkdj';
  static const String vimeusApiKey = 'ak_2FuYwz74JOI0rrNdWeI9CCEIJoTixbHB';
  static const String vimeusViewKey = 'uxAbTyUVC_U2qCvN8id5C5x3lclqfoyBoEWQz06tWT4';
  static final String tmdbApiKey = (() {
    const tmdb = String.fromEnvironment('TMDB_API_KEY');
    const viteTmdb = String.fromEnvironment('VITE_TMDB_API_KEY');
    if (tmdb.isNotEmpty) return tmdb;
    if (viteTmdb.isNotEmpty) return viteTmdb;
    return '7f14e9c61f345dc915781e02cde0e084';
  })();
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p/';

  static String wrapUrl(String url) {
    if (kIsWeb) {
      if (kReleaseMode) {
        if (url.startsWith('https://vimeus.com/api/')) {
          return url.replaceFirst('https://vimeus.com/api/', '/vimeus-api/');
        } else if (url.startsWith('https://vimeus.com/e/')) {
          return url.replaceFirst('https://vimeus.com/e/', '/vimeus-embed/');
        } else if (url.startsWith('https://server.bixplay.online/')) {
          return url.replaceFirst('https://server.bixplay.online/', '/bixplay-server/');
        } else if (url.startsWith('https://appnew2.bixplay.online/rest-api/v100/')) {
          return url.replaceFirst('https://appnew2.bixplay.online/rest-api/v100/', '/bixplay-api/');
        } else if (url.startsWith('https://appnew2.bixplay.online/api/')) {
          return url.replaceFirst('https://appnew2.bixplay.online/api/', '/bixplay-search/');
        }
      }
      // Local dev - relying on --disable-web-security flag
      return url;
    }
    return url;
  }

  final Dio _dio;
  final Dio _searchDio;
  final Dio _tmdbDio;
  final Map<String, Map<String, dynamic>?> _tmdbCache = {};

  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {
              'API-KEY': apiKey,
            },
          ),
        ),
        _searchDio = Dio(
          BaseOptions(
            baseUrl: searchBaseUrl,
          ),
        ),
        _tmdbDio = Dio(
          BaseOptions(
            baseUrl: 'https://api.themoviedb.org/3/',
            queryParameters: {
              'api_key': tmdbApiKey,
              'language': 'es-ES',
            },
            headers: const {'accept': 'application/json'},
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        ) {
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: print,
    ));

    if (kIsWeb) {
      final corsInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          final fullUrl = options.uri.toString();
          if (kReleaseMode) {
            // Rewrite URL paths using Netlify CDN redirects to bypass CORS
            if (fullUrl.startsWith(baseUrl)) {
              options.path = fullUrl.replaceFirst(baseUrl, '/bixplay-api/');
            } else if (fullUrl.startsWith(searchBaseUrl)) {
              options.path = fullUrl.replaceFirst(searchBaseUrl, '/bixplay-search/');
            }
            options.baseUrl = '';
            options.queryParameters = {};
          } else {
            // Local dev - relying on --disable-web-security flag
            // No proxy needed
          }
          return handler.next(options);
        },
      );
      _searchDio.interceptors.add(corsInterceptor);
      _dio.interceptors.add(corsInterceptor);
    }
  }




  // Get Configuration Data
  Future<Map<String, dynamic>> getConfig() async {
    try {
      final response = await _dio.get('config');
      return response.data;
    } catch (e) {
      await captureAndLogError(source: 'api.getConfig', error: e);
      throw Exception('Failed to load config: $e');
    }
  }

  // Get Movies
  Future<List<dynamic>> getMovies({int page = 1}) async {
    try {
      final response = await _dio.get(
        'movies',
        queryParameters: {'page': page},
      );
      // Depending on the response structure, this might need adjustment.
      // Usually it's either a list directly, or a map with a data array.
      final int tmdbLimit = page == 1 ? 20 : 8;
      if (response.data is List) {
        return _enrichMediaListWithTmdb(List<dynamic>.from(response.data), isTv: false, maxItems: tmdbLimit);
      } else if (response.data is Map && response.data.containsKey('data')) {
        return _enrichMediaListWithTmdb(List<dynamic>.from(response.data['data']), isTv: false, maxItems: tmdbLimit);
      }
      return _enrichMediaListWithTmdb([response.data], isTv: false, maxItems: 1); // fallback
    } catch (e) {
      await captureAndLogError(source: 'api.getMovies', error: e);
      throw Exception('Failed to load movies: $e');
    }
  }

  // Live TV
  Future<List<dynamic>> getLiveTv() async {
    try {
      final response = await _dio.get('all_tv_channel_by_category'); 
      return response.data is List ? response.data : [response.data];
    } catch (e) {
      // Falback to another endpoint if the exact one is different
      try {
        final res2 = await _dio.get('tv_channels');
        return res2.data is List ? res2.data : [res2.data];
      } catch (e2) {
        await captureAndLogError(source: 'api.getLiveTv.fallback', error: e2);
        throw Exception('Failed to load live tv: $e');
      }
    }
  }

  // Search
  Future<List<dynamic>> search(String query, {int page = 1}) async {
    final raw = query.trim();
    if (raw.isEmpty) return [];

    try {
      final List<dynamic> allResults = [];

      // Primary search endpoint from original APK reverse engineering.
      // GET /api/search?api_secret_key=...&q=...&page=...
      try {
        final response = await _searchDio.get(
          'search',
          queryParameters: {
            'api_secret_key': searchApiKey,
            'q': raw,
            'page': page,
          },
        );
        if (response.data is Map) {
          if (response.data['movie'] is List) allResults.addAll(response.data['movie']);
          if (response.data['tvseries'] is List) allResults.addAll(response.data['tvseries']);
          if (response.data['live_tv'] is List) allResults.addAll(response.data['live_tv']);
          if (response.data['tv_channels'] is List) allResults.addAll(response.data['tv_channels']);
        }
      } catch (e) {
        await captureAndLogError(source: 'api.search.primary', error: e);
      }

      // Compatibility fallback to old endpoint.
      try {
        final safeQuery = Uri.encodeComponent(raw);
        final response = await _dio.get('search/$safeQuery/$page');
        if (response.data is Map) {
          if (response.data['movie'] is List) allResults.addAll(response.data['movie']);
          if (response.data['tvseries'] is List) allResults.addAll(response.data['tvseries']);
          if (response.data['live_tv'] is List) allResults.addAll(response.data['live_tv']);
          if (response.data['tv_channels'] is List) allResults.addAll(response.data['tv_channels']);
        } else if (response.data is List) {
          allResults.addAll(response.data);
        }
      } catch (e) {
        await captureAndLogError(source: 'api.search.legacy', error: e);
      }

      // Add live channels by client-side match when API omits live results.
      if (page == 1) {
        try {
          final liveChannels = await getLiveTv();
          final q = raw.toLowerCase();
          final liveMatches = liveChannels.where((item) {
            final name = (item['channel_name'] ?? item['title'] ?? '').toString().toLowerCase();
            return name.contains(q);
          });
          allResults.addAll(liveMatches);
        } catch (_) {
          // Keep search resilient even if live endpoint fails.
        }
      }

      final deduped = _dedupeResults(allResults);
      return _enrichSearchResultsWithTmdb(deduped, maxItems: page == 1 ? 20 : 8);
    } catch (e) {
      await captureAndLogError(source: 'api.search', error: e);
      throw Exception('Failed to search: $e');
    }
  }

  List<dynamic> _dedupeResults(List<dynamic> input) {
    final seen = <String>{};
    final out = <dynamic>[];

    for (final item in input) {
      final id = (item['videos_id'] ?? item['movies_id'] ?? item['live_tv_id'] ?? item['stream_id'] ?? '').toString();
      final type = (item['is_tvseries']?.toString() == '1' || item['tv_name'] != null)
          ? 'tvseries'
          : (item['stream_url'] != null || item['channel_name'] != null || item['live_tv_id'] != null)
              ? 'live'
              : 'movie';
      final key = '$type::$id::${(item['title'] ?? item['tv_name'] ?? item['channel_name'] ?? '').toString()}';

      if (!seen.contains(key)) {
        seen.add(key);
        out.add(item);
      }
    }
    return out;
  }

  Future<List<dynamic>> searchLocalFallback(String query, {int maxPages = 4}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final List<dynamic> merged = [];
    for (int page = 1; page <= maxPages; page++) {
      try {
        final movies = await getMovies(page: page);
        final tv = await getTvSeries(page: page);
        merged.addAll(movies);
        merged.addAll(tv);
      } catch (_) {
        // Keep partial results if one page fails
      }
    }

    bool matches(dynamic item) {
      final title = (item['title'] ?? item['tv_name'] ?? '').toString().toLowerCase();
      final desc = (item['description'] ?? '').toString().toLowerCase();
      return title.contains(q) || desc.contains(q);
    }

    final filtered = merged.where(matches).toList();
    return _enrichSearchResultsWithTmdb(filtered, maxItems: 16);
  }

  // Get TV Series
  Future<List<dynamic>> getTvSeries({int page = 1}) async {
    try {
      final response = await _dio.get('tvseries', queryParameters: {'page': page});
      final int tmdbLimit = page == 1 ? 20 : 8;
      if (response.data is List) {
        return _enrichMediaListWithTmdb(List<dynamic>.from(response.data), isTv: true, maxItems: tmdbLimit);
      }
      if (response.data is Map && response.data.containsKey('data')) {
        return _enrichMediaListWithTmdb(List<dynamic>.from(response.data['data']), isTv: true, maxItems: tmdbLimit);
      }
      return _enrichMediaListWithTmdb([response.data], isTv: true, maxItems: 1);
    } catch (e) {
      await captureAndLogError(source: 'api.getTvSeries', error: e);
      throw Exception('Failed to load tv series: $e');
    }
  }

  // Get Single Details (Movies/Series/Live TV)
  Future<Map<String, dynamic>> getSingleDetails(String type, String id) async {
    String apiType = type;
    if (type == 'movies') apiType = 'movie';
    if (type == 'live') apiType = 'tv';
    
    try {
      final endpoint = (apiType == 'tv') ? 'single_details' : 'single_details_new';
      final response = await _dio.get(endpoint, queryParameters: {'type': apiType, 'id': id});
      dynamic data = response.data;
      if (data is List && data.isNotEmpty) {
        data = data.first;
      }
      if (data is Map) {
        final base = Map<String, dynamic>.from(data);
        final enriched = await _enrichMediaItemWithTmdb(
          base,
          isTvHint: apiType == 'tvseries' || apiType == 'tv',
        );
        return enriched;
      }
      throw Exception('Invalid data format');
    } catch (e) {
      try {
        final fallbackEndpoint = (apiType == 'tv') ? 'single_details_new' : 'single_details';
        final response = await _dio.get(fallbackEndpoint, queryParameters: {'type': apiType, 'id': id});
        dynamic data = response.data;
        if (data is List && data.isNotEmpty) {
          data = data.first;
        }
        if (data is Map) {
          final base = Map<String, dynamic>.from(data);
          final enriched = await _enrichMediaItemWithTmdb(
            base,
            isTvHint: apiType == 'tvseries' || apiType == 'tv',
          );
          return enriched;
        }
      } catch (_) {}
      await captureAndLogError(source: 'api.getSingleDetails', error: e);
      return {
        'videos_id': id,
        'title': 'Contenido',
        'description': 'Detalles no disponibles temporalmente.',
        'videos': [],
      };
    }
  }

  Future<List<dynamic>> _enrichSearchResultsWithTmdb(List<dynamic> input, {int maxItems = 16}) async {
    if (!_tmdbEnabled || input.isEmpty) return input;

    final safe = List<dynamic>.from(input);
    final futures = <Future<Map<String, dynamic>>>[];
    final indexes = <int>[];
    final cap = maxItems.clamp(0, safe.length);

    for (int i = 0; i < safe.length; i++) {
      final raw = safe[i];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw as Map);
      final bool isLive = map['stream_url'] != null || map['channel_name'] != null || map['live_tv_id'] != null;
      if (isLive) continue;
      if (indexes.length >= cap) break;
      indexes.add(i);
      final isTv = map['is_tvseries'] == '1' || map['tv_name'] != null;
      futures.add(_enrichMediaItemWithTmdb(map, isTvHint: isTv));
    }

    if (futures.isEmpty) return safe;
    final enriched = await Future.wait(futures);
    for (int i = 0; i < indexes.length; i++) {
      safe[indexes[i]] = enriched[i];
    }
    return safe;
  }

  Future<List<dynamic>> _enrichMediaListWithTmdb(
    List<dynamic> input, {
    required bool isTv,
    int maxItems = 16,
  }) async {
    if (!_tmdbEnabled || input.isEmpty) return input;

    final safe = List<dynamic>.from(input);
    final futures = <Future<Map<String, dynamic>>>[];
    final indexes = <int>[];
    final cap = maxItems.clamp(0, safe.length);

    for (int i = 0; i < cap; i++) {
      final raw = safe[i];
      if (raw is! Map) continue;
      indexes.add(i);
      futures.add(_enrichMediaItemWithTmdb(Map<String, dynamic>.from(raw as Map), isTvHint: isTv));
    }

    if (futures.isEmpty) return safe;
    final enriched = await Future.wait(futures);
    for (int i = 0; i < indexes.length; i++) {
      safe[indexes[i]] = enriched[i];
    }
    return safe;
  }

  Future<Map<String, dynamic>> _enrichMediaItemWithTmdb(
    Map<String, dynamic> item, {
    required bool isTvHint,
  }) async {
    if (!_tmdbEnabled) return item;
    try {
      final tmdb = await _resolveTmdbData(item, isTvHint: isTvHint);
      if (tmdb == null) return item;
      return _mergeItemWithTmdb(item, tmdb);
    } catch (_) {
      return item;
    }
  }

  bool get _tmdbEnabled => tmdbApiKey.trim().isNotEmpty;

  Future<Map<String, dynamic>?> _resolveTmdbData(Map<String, dynamic> item, {required bool isTvHint}) async {
    if (!_tmdbEnabled) return null;

    final tmdbId = _toCleanString(item['tmdb_id'] ?? item['tmdb'] ?? item['id_tmdb']);
    final imdbId = _normalizeImdbId(item['imdb_id'] ?? item['imdb']);
    final title = _toCleanString(item['title'] ?? item['tv_name'] ?? item['name']);
    final year = _extractYear(item);
    final contentType = isTvHint ? 'tv' : 'movie';

    final cacheKey = 't:$contentType|tmdb:$tmdbId|imdb:$imdbId|q:${title.toLowerCase()}|y:${year ?? ''}';
    if (_tmdbCache.containsKey(cacheKey)) return _tmdbCache[cacheKey];

    Map<String, dynamic>? tmdb;

    if (tmdbId.isNotEmpty) {
      tmdb = await _getTmdbDetailsById(contentType, int.tryParse(tmdbId));
    }

    if (tmdb == null && imdbId != null) {
      tmdb = await _findTmdbByImdb(imdbId, preferredType: contentType);
    }

    if (tmdb == null && title.isNotEmpty) {
      tmdb = await _searchTmdbByTitle(title, year: year, preferredType: contentType);
    }

    _tmdbCache[cacheKey] = tmdb;
    return tmdb;
  }

  Future<Map<String, dynamic>?> _findTmdbByImdb(String imdbId, {required String preferredType}) async {
    try {
      final response = await _tmdbDio.get(
        'find/$imdbId',
        queryParameters: {'external_source': 'imdb_id'},
      );
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;
      if (data == null) return null;

      List<dynamic> hits = [];
      if (preferredType == 'tv') {
        hits = data['tv_results'] is List ? List<dynamic>.from(data['tv_results']) : [];
        if (hits.isEmpty && data['movie_results'] is List) {
          hits = List<dynamic>.from(data['movie_results']);
        }
      } else {
        hits = data['movie_results'] is List ? List<dynamic>.from(data['movie_results']) : [];
        if (hits.isEmpty && data['tv_results'] is List) {
          hits = List<dynamic>.from(data['tv_results']);
        }
      }

      if (hits.isEmpty) return null;
      final first = hits.first;
      if (first is! Map) return null;
      final id = int.tryParse(_toCleanString((first as Map)['id']));
      final actualType = (preferredType == 'tv' || (first['name'] != null && first['title'] == null)) ? 'tv' : 'movie';
      return _getTmdbDetailsById(actualType, id);
    } catch (e) {
      await captureAndLogError(source: 'tmdb.findByImdb', error: e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _searchTmdbByTitle(
    String title, {
    required String preferredType,
    int? year,
  }) async {
    try {
      final endpoint = preferredType == 'tv' ? 'search/tv' : 'search/movie';
      final qp = <String, dynamic>{'query': title, 'include_adult': false};
      if (year != null) {
        if (preferredType == 'tv') {
          qp['first_air_date_year'] = year;
        } else {
          qp['year'] = year;
        }
      }

      final response = await _tmdbDio.get(endpoint, queryParameters: qp);
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;
      final results = data?['results'] is List ? List<dynamic>.from(data!['results']) : <dynamic>[];

      if (results.isEmpty) {
        final fallback = await _tmdbDio.get(
          'search/multi',
          queryParameters: {'query': title, 'include_adult': false},
        );
        final fData = fallback.data is Map<String, dynamic> ? fallback.data as Map<String, dynamic> : null;
        final fResults = fData?['results'] is List ? List<dynamic>.from(fData!['results']) : <dynamic>[];
        final candidate = fResults.cast<Map>().firstWhere(
              (r) => (r['media_type']?.toString() == preferredType),
              orElse: () => <String, dynamic>{},
            );
        if (candidate.isEmpty) return null;
        final id = int.tryParse(_toCleanString(candidate['id']));
        return _getTmdbDetailsById(preferredType, id);
      }

      Map<String, dynamic>? best;
      for (final r in results) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r as Map);
        if (best == null) {
          best = m;
          continue;
        }
        final currentVotes = (m['vote_count'] as num?)?.toDouble() ?? 0.0;
        final bestVotes = (best['vote_count'] as num?)?.toDouble() ?? 0.0;
        if (currentVotes > bestVotes) {
          best = m;
        }
      }

      if (best == null) return null;
      final id = int.tryParse(_toCleanString(best['id']));
      return _getTmdbDetailsById(preferredType, id);
    } catch (e) {
      await captureAndLogError(source: 'tmdb.searchByTitle', error: e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getTmdbDetailsById(String type, int? id) async {
    if (id == null) return null;
    try {
      final response = await _tmdbDio.get(
        '$type/$id',
        queryParameters: {'append_to_response': 'external_ids'},
      );
      final data = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;
      if (data == null) return null;
      return _normalizeTmdbData(data, type: type);
    } catch (e) {
      await captureAndLogError(source: 'tmdb.details.$type', error: e);
      return null;
    }
  }

  Map<String, dynamic> _normalizeTmdbData(Map<String, dynamic> raw, {required String type}) {
    final posterPath = _toCleanString(raw['poster_path']);
    final backdropPath = _toCleanString(raw['backdrop_path']);
    final ext = raw['external_ids'] is Map<String, dynamic>
        ? raw['external_ids'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final imdbId = _normalizeImdbId(raw['imdb_id'] ?? ext['imdb_id']);
    final tmdbId = _toCleanString(raw['id']);
    final title = _toCleanString(raw['title'] ?? raw['name']);
    final overview = _toCleanString(raw['overview']);
    final rating = (raw['vote_average'] as num?)?.toDouble();
    final releaseDate = _toCleanString(raw['release_date'] ?? raw['first_air_date']);
    final runtime = raw['runtime'] ?? ((raw['episode_run_time'] is List && (raw['episode_run_time'] as List).isNotEmpty)
            ? (raw['episode_run_time'] as List).first
            : null);

    final genres = raw['genres'] is List
        ? (raw['genres'] as List)
            .whereType<Map>()
            .map((g) => _toCleanString((g as Map)['name']))
            .where((name) => name.isNotEmpty)
            .toList()
        : <String>[];

    return <String, dynamic>{
      'tmdb_id': tmdbId,
      'imdb_id': imdbId,
      'title': title,
      'tmdb_overview': overview,
      'tmdb_rating': rating?.toStringAsFixed(1),
      'tmdb_release_date': releaseDate,
      'tmdb_runtime': runtime?.toString(),
      'tmdb_genres': genres.join(', '),
      'tmdb_poster_url': posterPath.isEmpty ? '' : _tmdbImageUrl(posterPath, size: 'w780'),
      'tmdb_backdrop_url': backdropPath.isEmpty ? '' : _tmdbImageUrl(backdropPath, size: 'w1280'),
      'tmdb_type': type,
    };
  }

  Map<String, dynamic> _mergeItemWithTmdb(Map<String, dynamic> item, Map<String, dynamic> tmdb) {
    final out = Map<String, dynamic>.from(item);

    final tmdbPoster = _toCleanString(tmdb['tmdb_poster_url']);
    final tmdbBackdrop = _toCleanString(tmdb['tmdb_backdrop_url']);

    final currentPoster = _toCleanString(out['poster_url']);
    final currentThumb = _toCleanString(out['thumbnail_url']);

    final shouldUpgradePoster = tmdbPoster.isNotEmpty &&
        (currentPoster.isEmpty || _looksLowQualityImageUrl(currentPoster) || _looksLowQualityImageUrl(currentThumb));

    if (shouldUpgradePoster) {
      out['poster_url'] = tmdbPoster;
      if (_toCleanString(out['thumbnail_url']).isEmpty || _looksLowQualityImageUrl(currentThumb)) {
        out['thumbnail_url'] = tmdbPoster;
      }
    }

    if (tmdbBackdrop.isNotEmpty && _toCleanString(out['image_url']).isEmpty) {
      out['image_url'] = tmdbBackdrop;
    }

    final tmdbOverview = _toCleanString(tmdb['tmdb_overview']);
    if (tmdbOverview.isNotEmpty && _toCleanString(out['description']).isEmpty) {
      out['description'] = tmdbOverview;
    }

    final tmdbRating = _toCleanString(tmdb['tmdb_rating']);
    if (tmdbRating.isNotEmpty && _toCleanString(out['imdb_rating']).isEmpty) {
      out['imdb_rating'] = tmdbRating;
    }

    final tmdbRelease = _toCleanString(tmdb['tmdb_release_date']);
    if (tmdbRelease.isNotEmpty && _toCleanString(out['release']).isEmpty) {
      out['release'] = tmdbRelease;
    }

    final tmdbRuntime = _toCleanString(tmdb['tmdb_runtime']);
    if (tmdbRuntime.isNotEmpty && _toCleanString(out['runtime']).isEmpty) {
      out['runtime'] = tmdbRuntime;
    }

    final tmdbGenres = _toCleanString(tmdb['tmdb_genres']);
    if (tmdbGenres.isNotEmpty && _toCleanString(out['genre']).isEmpty) {
      out['genre'] = tmdbGenres;
    }

    final tmdbId = _toCleanString(tmdb['tmdb_id']);
    if (tmdbId.isNotEmpty && _toCleanString(out['tmdb_id']).isEmpty) {
      out['tmdb_id'] = tmdbId;
    }

    final imdbId = _normalizeImdbId(tmdb['imdb_id']);
    if (imdbId != null && _normalizeImdbId(out['imdb_id']) == null) {
      out['imdb_id'] = imdbId;
    }

    return out;
  }

  bool _looksLowQualityImageUrl(String url) {
    if (url.isEmpty) return true;
    final u = url.toLowerCase();
    return u.contains('w92') ||
        u.contains('w154') ||
        u.contains('thumb') ||
        u.contains('small') ||
        u.contains('low');
  }

  String _tmdbImageUrl(String path, {String size = 'w780'}) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$tmdbImageBase$size$p';
  }

  int? _extractYear(Map<String, dynamic> item) {
    final candidates = [
      _toCleanString(item['release']),
      _toCleanString(item['release_date']),
      _toCleanString(item['year']),
      _toCleanString(item['title']),
      _toCleanString(item['tv_name']),
    ];
    for (final v in candidates) {
      final m = RegExp(r'(19|20)\d{2}').firstMatch(v);
      if (m != null) {
        return int.tryParse(m.group(0)!);
      }
    }
    return null;
  }

  String? _normalizeImdbId(dynamic value) {
    final v = _toCleanString(value).toLowerCase();
    if (v.isEmpty) return null;
    final match = RegExp(r'tt\d{6,9}').firstMatch(v);
    if (match == null) return null;
    return match.group(0);
  }

  String _toCleanString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}
