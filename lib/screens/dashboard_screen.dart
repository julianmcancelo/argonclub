import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../theme/argon_theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'diagnostics_screen.dart';
import 'details_screen.dart';
import 'settings_screen.dart';
import 'watch_party_lobby_screen.dart';

import '../services/error_logger.dart';
import '../services/watch_history.dart';
import '../services/my_list_service.dart';
import '../services/watch_party_service.dart';
import '../widgets/remote_control_status_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  List<dynamic> _continueWatching = [];
  List<dynamic> _recentMovies = [];
  List<dynamic> _recentSeries = [];
  List<dynamic> _liveChannels = [];
  List<dynamic> _top10Mixed = [];
  List<dynamic> _dramaSeries = [];
  List<dynamic> _animePicks = [];
  List<dynamic> _classicsPicks = [];
  List<dynamic> _myListItems = [];

  String _timeString = '';
  String _dateString = '';
  late Timer _timer;

  // Custom tweak settings for style
  String _accentName = 'Mono';
  bool _atmosphere = false;
  late AnimationController _auroraController;

  static const Color colorBg = Color(0xFF020A14);
  static const Color colorBg2 = ArgonTheme.navy;
  static const Color colorSurface = Color(0x12161618);
  static const Color colorSurface2 = Color(0xCC17171A);
  static const Color colorLine = Color(0x22FFFFFF);
  static const Color colorLineStrong = Color(0x42FFFFFF);
  static const Color colorInk = ArgonTheme.white;
  static const Color colorInk2 = Color(0xFFD9ECF8);
  static const Color colorInk3 = Color(0xFF86A7C0);
  static const Color colorCrimson = ArgonTheme.sky;
  static const Color colorCrimsonSoft = ArgonTheme.skyBright;
  static const Color colorFire = ArgonTheme.gold;
  static const Color colorGlass = Color(0xB3121215);
  static const Color colorGlassStrong = Color(0xD91A1A1E);

  // Dynamic branding and accents based on user tweaks (Mono, Arena, Niebla)
  Color get currentAccentColor {
    switch (_accentName) {
      case 'Arena':
        return ArgonTheme.gold;
      case 'Niebla':
        return ArgonTheme.skyBright;
      case 'Mono':
      default:
        return colorCrimsonSoft;
    }
  }

  Color get colorBrandA => currentAccentColor;
  Color get colorBrandB =>
      _accentName == 'Mono' ? colorFire : currentAccentColor;
  Color get colorAccentNeutral => currentAccentColor;

  // Category Accents
  Color get accentPeliculas => currentAccentColor;
  Color get accentSeries => currentAccentColor;
  Color get accentAnime => currentAccentColor;
  Color get accentTelenovelas => currentAccentColor;
  Color get accentTV => currentAccentColor;
  Color get accentBuscar => currentAccentColor;
  Color get accentErrores => currentAccentColor;
  Color get accentAjustes => currentAccentColor;

  // Profile avatar colors / gradients
  static const List<List<Color>> avatarGradients = [
    [Color(0xFF00B0FF), Color(0xFF6200EE)], // Blue-Purple
    [Color(0xFFE040FB), Color(0xFF8E24AA)], // Magenta-Pink
    [Color(0xFFFF5722), Color(0xFFE91E63)], // Orange-Red
    [Color(0xFFFFC107), Color(0xFFFF9800)], // Amber-Gold
    [Color(0xFF00E676), Color(0xFF00B0FF)], // Emerald-Cyan
  ];

  // Profile management variables
  List<Map<String, dynamic>> _profiles = [];
  Map<String, dynamic>? _activeProfile;
  bool _showProfileSelector = false;
  bool _showDropdownMenu = false;

  // Auto-Slideshow variables
  Timer? _slideshowTimer;
  int _currentSlideIndex = 0;
  bool _isManualSelection = false;
  final List<FocusNode> _categoryFocusNodes = [];

  // Dynamic Hero Billboard data
  String _focusedBackdropUrl = '';
  String _focusedTitle = '';
  String _focusedDesc = '';
  String _focusedRating = '8.5';
  String _focusedYear = '2026';
  String _focusedDuration = '2 h 14 min';
  String _focusedGenres = 'Ciencia ficción · Drama';
  String _focusedType = 'movie';
  String _focusedId = '';
  dynamic _focusedItemData;

  double _tvScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return (width / 1920).clamp(0.82, 1.18);
  }

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat(reverse: true);
    _loadProfilesAndData();
    _updateDateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateDateTime(),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _slideshowTimer?.cancel();
    _auroraController.dispose();
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureCategoryFocusNodes(int count) {
    while (_categoryFocusNodes.length < count) {
      _categoryFocusNodes.add(
        FocusNode(debugLabel: 'category_${_categoryFocusNodes.length}'),
      );
    }
    while (_categoryFocusNodes.length > count) {
      _categoryFocusNodes.removeLast().dispose();
    }
  }

  void _updateDateTime() {
    final now = DateTime.now();
    final timeFormatted = DateFormat('HH:mm').format(now);
    final dateFormatted = DateFormat(
      'EEEE, d MMMM',
      'es',
    ).format(now); // Spanish dynamic format

    // Capitalize first letter of date
    String dateStr = dateFormatted;
    if (dateFormatted.isNotEmpty) {
      dateStr = dateFormatted[0].toUpperCase() + dateFormatted.substring(1);
    }

    if (mounted) {
      setState(() {
        _timeString = timeFormatted;
        _dateString = dateStr;
      });
    }
  }

  Future<void> _loadProfilesAndData() async {
    // 1. Fetch Movies and Series first
    try {
      final movies = await _apiClient.getMovies(page: 1);
      final series = await _apiClient.getTvSeries(page: 1);
      final continueWatching = await WatchHistoryService.getContinueWatching(
        limit: 12,
      );

      List<dynamic> liveChannels = [];
      try {
        liveChannels = await _apiClient.getLiveTv();
      } catch (e) {
        debugPrint('DASHBOARD LIVE TV LOAD ERROR: $e');
      }

      _recentMovies = movies.take(12).toList();
      _recentSeries = series.take(12).toList();
      _continueWatching = continueWatching;
      _liveChannels = liveChannels.take(12).toList();

      _buildThematicRows(_recentMovies, _recentSeries);
      _isLoading = false;

      final dynamic initialSlide = _recentSeries.isNotEmpty
          ? _recentSeries.first
          : (_recentMovies.isNotEmpty ? _recentMovies.first : null);
      if (initialSlide != null) {
        _updateFocusedItem(
          initialSlide,
          initialSlide['is_tvseries'] == '1' ? 'tvseries' : 'movie',
        );
      }
    } catch (e, st) {
      debugPrint('DASHBOARD DATA LOAD ERROR: $e');
      debugPrint(st.toString());
      await captureAndLogError(
        source: 'dashboard.loadData',
        error: e,
        stackTrace: st,
      );
      _recentMovies = [];
      _recentSeries = [];
      _liveChannels = [];
      _continueWatching = [];
      _buildThematicRows(_recentMovies, _recentSeries);
      _isLoading = false;
      final dynamic initialSlide = _recentSeries.isNotEmpty
          ? _recentSeries.first
          : (_recentMovies.isNotEmpty ? _recentMovies.first : null);
      if (initialSlide != null) {
        _updateFocusedItem(
          initialSlide,
          initialSlide['is_tvseries'] == '1' ? 'tvseries' : 'movie',
        );
      }
    }
    // 2. Load profiles and tweak settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    _accentName = prefs.getString('argon_tweak_accent') ?? 'Mono';
    _atmosphere = prefs.getBool('argon_tweak_atmosphere') ?? false;

    final profilesJson = prefs.getStringList('argon_profiles') ?? [];

    if (profilesJson.isEmpty) {
      // Setup default "Invitado" profile if completely empty
      final defaultProfile = {
        'id': '1',
        'name': 'Invitado',
        'avatar': 'I',
        'gradientIndex': 0,
      };
      _profiles = [defaultProfile];
      await prefs.setStringList('argon_profiles', [jsonEncode(defaultProfile)]);
      _activeProfile = defaultProfile;
      _showProfileSelector = true;
    } else {
      _profiles = profilesJson
          .map((p) => Map<String, dynamic>.from(jsonDecode(p)))
          .toList();
      final activeId = prefs.getString('argon_active_profile_id');

      _activeProfile = _profiles.firstWhere(
        (p) => p['id'] == activeId,
        orElse: () => _profiles[0],
      );

      if (activeId == null) {
        _showProfileSelector = true;
      }
    }

    if (_activeProfile != null) {
      _myListItems = await MyListService.getItems(
        _activeProfile!['id'].toString(),
      );
    }

    setState(() {});

    if (!_showProfileSelector) {
      _startSlideshow();
    }
  }

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!_isLoading && _recentMovies.isNotEmpty && !_isManualSelection) {
        setState(() {
          final maxSlide = _recentMovies.length.clamp(0, 5);
          if (maxSlide > 0) {
            _currentSlideIndex = (_currentSlideIndex + 1) % maxSlide;
            _updateFocusedItem(_recentMovies[_currentSlideIndex], 'movie');
          }
        });
      }
    });
  }

  Future<void> _selectProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('argon_active_profile_id', profile['id'] as String);
    setState(() {
      _activeProfile = profile;
      _showProfileSelector = false;
      _showDropdownMenu = false;
    });
    _startSlideshow();
  }

  Future<void> _addNewProfile(String name, int gradientIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    final newProfile = {
      'id': newId,
      'name': name,
      'avatar': initial,
      'gradientIndex': gradientIndex,
    };

    _profiles.add(newProfile);

    final listJson = _profiles.map((p) => jsonEncode(p)).toList();
    await prefs.setStringList('argon_profiles', listJson);

    setState(() {});
  }

  Future<void> _deleteProfile(Map<String, dynamic> profile) async {
    if (_profiles.length <= 1) return; // Prevent deleting the last profile

    final prefs = await SharedPreferences.getInstance();
    _profiles.removeWhere((p) => p['id'] == profile['id']);

    final listJson = _profiles.map((p) => jsonEncode(p)).toList();
    await prefs.setStringList('argon_profiles', listJson);

    if (_activeProfile?['id'] == profile['id']) {
      _activeProfile = _profiles[0];
      await prefs.setString(
        'argon_active_profile_id',
        _activeProfile!['id'] as String,
      );
    }

    setState(() {});
  }

  void _showAddProfileDialog() {
    final textController = TextEditingController();
    int selectedGradIndex = 0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colorBg2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: colorLineStrong, width: 1.5),
              ),
              title: Text(
                'Crear Perfil',
                style: GoogleFonts.sora(
                  color: colorInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nombre del perfil:',
                    style: GoogleFonts.outfit(color: colorInk2, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: textController,
                    style: GoogleFonts.outfit(color: colorInk),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Ingresa tu nombre',
                      hintStyle: GoogleFonts.outfit(color: colorInk3),
                      filled: true,
                      fillColor: colorSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: colorLine),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorBrandA, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Selecciona un color de avatar:',
                    style: GoogleFonts.outfit(color: colorInk2, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (index) {
                      final isSelected = selectedGradIndex == index;
                      return Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.select)) {
                            setDialogState(() => selectedGradIndex = index);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final focused = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: () {
                                setDialogState(() => selectedGradIndex = index);
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: avatarGradients[index],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : (focused
                                              ? colorInk2
                                              : Colors.transparent),
                                    width: isSelected
                                        ? 3.0
                                        : (focused ? 2.0 : 0.0),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: avatarGradients[index][0]
                                                .withOpacity(0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : [],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.outfit(
                      color: colorInk3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorBrandA,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final name = textController.text.trim();
                    if (name.isNotEmpty) {
                      await _addNewProfile(name, selectedGradIndex);
                      Navigator.pop(context);
                    }
                  },
                  child: Text(
                    'Guardar',
                    style: GoogleFonts.outfit(
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

  Future<void> _setAccent(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('argon_tweak_accent', name);
    setState(() {
      _accentName = name;
    });
  }

  Future<void> _setAtmosphere(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('argon_tweak_atmosphere', enabled);
    setState(() {
      _atmosphere = enabled;
    });
  }

  Widget _buildAuroraBackground() {
    if (!_atmosphere) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _auroraController,
      builder: (context, child) {
        final val = _auroraController.value;
        // Translate values for slow floating effect
        final dx1 = 50.0 * val;
        final dy1 = 30.0 * (1.0 - val);
        final dx2 = -40.0 * val;
        final dy2 = 40.0 * val;
        final dx3 = 30.0 * val;
        final dy3 = -30.0 * val;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Blob 1: Top-Right
            Positioned(
              top: -260 + dy1,
              right: -140 + dx1,
              child: _buildAuroraBlob(
                size: 1000,
                color: currentAccentColor.withOpacity(0.12),
              ),
            ),
            // Blob 2: Middle-Left
            Positioned(
              top: 560 + dy2,
              left: -220 + dx2,
              child: _buildAuroraBlob(
                size: 840,
                color: currentAccentColor.withOpacity(0.09),
              ),
            ),
            // Blob 3: Bottom-Right
            Positioned(
              top: 1200 + dy3,
              right: 150 + dx3,
              child: _buildAuroraBlob(
                size: 760,
                color: currentAccentColor.withOpacity(0.08),
              ),
            ),
            // Blob 4: Lower-Left
            Positioned(
              top: 1800 - dy1,
              left: 100 - dx2,
              child: _buildAuroraBlob(
                size: 620,
                color: currentAccentColor.withOpacity(0.10),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuroraBlob({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0.3), Colors.transparent],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  void _showTweaksDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161622).withOpacity(0.96),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: colorLineStrong, width: 1.5),
              ),
              title: Text(
                'Tweaks / Estética',
                style: GoogleFonts.sora(
                  color: colorInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acento de color:',
                    style: GoogleFonts.outfit(color: colorInk2, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  // Accent Selector Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['Mono', 'Arena', 'Niebla'].map((accent) {
                      final isSelected = _accentName == accent;
                      return Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.select)) {
                            _setAccent(accent);
                            setDialogState(() {});
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final focused = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: () {
                                _setAccent(accent);
                                setDialogState(() {});
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? currentAccentColor.withOpacity(0.2)
                                      : (focused
                                            ? colorSurface2
                                            : colorSurface),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? currentAccentColor
                                        : (focused
                                              ? colorLineStrong
                                              : colorLine),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  accent,
                                  style: GoogleFonts.outfit(
                                    color: isSelected
                                        ? Colors.white
                                        : colorInk2,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Atmósfera (Aurora animada)',
                            style: GoogleFonts.outfit(
                              color: colorInk,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Blobs de luz flotantes en fondo',
                            style: GoogleFonts.outfit(
                              color: colorInk3,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.select)) {
                            _setAtmosphere(!_atmosphere);
                            setDialogState(() {});
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Switch(
                          value: _atmosphere,
                          activeColor: currentAccentColor,
                          onChanged: (val) {
                            _setAtmosphere(val);
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cerrar',
                    style: GoogleFonts.outfit(
                      color: colorInk2,
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

  void _updateFocusedItem(dynamic item, String type) {
    if (item == null) return;
    setState(() {
      _focusedItemData = item;
      _focusedType = type;
      _focusedId = (item['movies_id'] ?? item['videos_id'] ?? item['id'] ?? '')
          .toString();
      _focusedTitle = (item['title'] ?? item['tv_name'] ?? '').toString();
      _focusedBackdropUrl =
          (item['tmdb_backdrop_url'] ??
                  item['backdrop_url'] ??
                  item['image_url'] ??
                  item['thumbnail_url'] ??
                  item['poster_url'] ??
                  '')
              .toString();
      _focusedDesc = (item['description'] ?? 'No hay descripción disponible.')
          .toString();
      _focusedRating = (item['rating'] ?? item['rating_number'] ?? '8.5')
          .toString();
      _focusedYear = (item['release_year'] ?? item['year'] ?? '2026')
          .toString();
      _focusedDuration =
          (item['duration'] ?? (type == 'movie' ? '2 h 14 min' : '1 Temporada'))
              .toString();
      _focusedGenres =
          (item['genres'] ??
                  (type == 'movie'
                      ? 'Ciencia ficción · Drama'
                      : 'Animación · Aventura'))
              .toString();
    });
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);
    final tvScale = _tvScale(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorBg,
        body: Center(child: CircularProgressIndicator(color: colorBrandA)),
      );
    }

    // Return gorgeous persistent Profile Selection screen overlay if required
    if (_showProfileSelector) {
      return _buildProfileSelectorScreen(isTV);
    }

    return Scaffold(
      backgroundColor: colorBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. DYNAMIC BACKDROP SLIDESHOW WITH SMOOTH CROSS-FADE
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _focusedBackdropUrl.isNotEmpty
                  ? CachedNetworkImage(
                      key: ValueKey<String>(_focusedBackdropUrl),
                      imageUrl: _focusedBackdropUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      memCacheWidth: isTV ? 960 : 640,
                    )
                  : Container(color: colorBg),
            ),
          ),

          // 2. BACKDROP GAUSSIAN BLUR BOKEH FILTER (Optimized for D-Pad TVs to avoid GPU lag)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isTV ? 4.0 : 10.0,
                sigmaY: isTV ? 4.0 : 10.0,
              ),
              child: Container(
                color: isTV ? colorBg.withOpacity(0.35) : Colors.transparent,
              ),
            ),
          ),

          // 3. CINEMATIC GRADIENT SCRIMS FOR MAXIMUM CONTRAST & DEPTH
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    colorBg.withOpacity(0.95),
                    colorBg.withOpacity(0.80),
                    colorBg.withOpacity(0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.30, 0.65, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    colorBg,
                    colorBg.withOpacity(0.85),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colorBg.withOpacity(0.70), Colors.transparent],
                  stops: const [0.0, 0.25],
                ),
              ),
            ),
          ),
          // 4. AURORA ATMOSPHERIC BACKGROUND (Flashing/breathing blobs)
          Positioned.fill(child: _buildAuroraBackground()),

          // 5. MAIN SCROLLABLE CONTENT
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTV ? 32.0 * tvScale : 20.0,
                vertical: isTV ? 10.0 * tvScale : 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Navigation bar & clock
                  _buildTopbar(isTV),
                  SizedBox(height: isTV ? 14 * tvScale : 32),

                  // Dynamic Billboard Hero Panel with indicators
                  _buildHeroBillboard(isTV),
                  SizedBox(height: isTV ? 20 * tvScale : 48),

                  // Glassmorphic Explore Categories Hub
                  _buildCategoryHub(isTV),
                  SizedBox(height: isTV ? 20 * tvScale : 48),

                  // Carrete "Continuar Viendo"
                  _buildLandscapeRow(
                    title: 'CONTINUAR VIENDO',
                    items: _continueWatching,
                    isTV: isTV,
                  ),
                  SizedBox(height: isTV ? 22 * tvScale : 48),

                  // Horizontal Movie Grid Carrete
                  _buildHorizontalRow(
                    title: 'PELÍCULAS ÚLTIMAS',
                    items: _recentMovies,
                    type: 'movie',
                    isTV: isTV,
                  ),
                  SizedBox(height: isTV ? 22 * tvScale : 48),

                  // Horizontal Series Grid Carrete
                  _buildHorizontalRow(
                    title: 'SERIES DESTACADAS',
                    items: _recentSeries,
                    type: 'tvseries',
                    isTV: isTV,
                  ),
                  SizedBox(height: isTV ? 22 * tvScale : 48),

                  // Horizontal Live TV Grid Carrete
                  _buildHorizontalRow(
                    title: 'CANALES EN VIVO',
                    items: _liveChannels,
                    type: 'live',
                    isTV: isTV,
                  ),
                  const SizedBox(height: 48),

                  // Navigation instructions
                  _buildFooterHint(isTV),
                ],
              ),
            ),
          ),

          // 5. DROPDOWN PROFILE MENU OVERLAY
          if (_showDropdownMenu)
            Positioned(
              top: isTV ? 72 * tvScale : 64,
              right: isTV ? 28 * tvScale : 20,
              child: _buildProfileDropdownMenu(isTV),
            ),
        ],
      ),
    );
  }

  // Top header with beautiful brand logo, time, and persistent profiles chip
  Widget _buildTopbar(bool isTV) {
    final tvScale = _tvScale(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Brand logo & Nav Items side-by-side
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'ARGON',
                      style: GoogleFonts.bebasNeue(
                        color: colorCrimson,
                        fontSize: isTV ? 34 * tvScale : 24,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'CLUB',
                      style: GoogleFonts.bebasNeue(
                        color: colorInk,
                        fontSize: isTV ? 34 * tvScale : 24,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Sala premium de peliculas y series'.toUpperCase(),
                  style: GoogleFonts.dmSans(
                    color: colorInk3,
                    fontSize: isTV ? 10 * tvScale : 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            if (isTV) ...[
              SizedBox(width: 34 * tvScale),
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Row(
                  children: [
                    _buildTopNavItem(
                      'Inicio',
                      isTV,
                      () {},
                      isActive: true,
                      focusOrder: const NumericFocusOrder(1),
                    ),
                    SizedBox(width: 12 * tvScale),
                    _buildTopNavItem(
                      'Películas',
                      isTV,
                      () => _navigateToPage(
                        const HomeScreen(
                          apiEndpoint: 'movies',
                          title: 'Peliculas',
                        ),
                      ),
                      focusOrder: const NumericFocusOrder(2),
                    ),
                    SizedBox(width: 12 * tvScale),
                    _buildTopNavItem(
                      'Series',
                      isTV,
                      () => _navigateToPage(
                        const HomeScreen(
                          apiEndpoint: 'tvseries',
                          title: 'Series',
                        ),
                      ),
                      focusOrder: const NumericFocusOrder(3),
                    ),

                    SizedBox(width: 12 * tvScale),
                    _buildTopNavItem(
                      'Mi Lista',
                      isTV,
                      () {},
                      focusOrder: const NumericFocusOrder(5),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),

        // Time clock and profile settings
        FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            children: [
              RemoteControlStatusCard(isTV: isTV),
              SizedBox(width: isTV ? 14 * tvScale : 10),
              // Live Clock
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeString,
                    style: GoogleFonts.dmSans(
                      color: colorInk,
                      fontSize: isTV ? 28 : 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateString,
                    style: GoogleFonts.dmSans(
                      color: colorInk3,
                      fontSize: isTV ? 13 : 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(width: isTV ? 14 * tvScale : 18),

              // Search Icon Shortcut
              _buildIconButton(
                icon: Icons.search_rounded,
                onPressed: () => _navigateToPage(const SearchScreen()),
                isTV: isTV,
                focusOrder: const NumericFocusOrder(10),
              ),
              SizedBox(width: isTV ? 8 * tvScale : 10),

              // Settings / Diagnostics Icon Shortcut
              _buildIconButton(
                icon: Icons.settings_outlined,
                onPressed: () => _navigateToPage(const SettingsScreen()),
                isTV: isTV,
                focusOrder: const NumericFocusOrder(11),
              ),
              SizedBox(width: isTV ? 8 * tvScale : 10),

              // Tweaks Icon Shortcut
              _buildIconButton(
                icon: Icons.palette_outlined,
                onPressed: _showTweaksDialog,
                isTV: isTV,
                focusOrder: const NumericFocusOrder(12),
              ),
              SizedBox(width: isTV ? 10 * tvScale : 12),

              // Profile Glassmorphic Badge with Dropdown Trigger
              _buildProfileBadge(isTV, focusOrder: const NumericFocusOrder(13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopNavItem(
    String label,
    bool isTV,
    VoidCallback onTap, {
    bool isActive = false,
    FocusOrder? focusOrder,
  }) {
    Widget child = Focus(
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
          final highlight = focused || isActive;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(
                horizontal: isTV ? 16 : 10,
                vertical: isTV ? 8 : 5,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: highlight ? Colors.white : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 120),
                style: GoogleFonts.dmSans(
                  color: highlight ? Colors.white : colorInk2,
                  fontSize: isTV ? 17 : 13,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isTV,
    FocusOrder? focusOrder,
  }) {
    Widget child = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _isManualSelection = false;
          _startSlideshow();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: isTV ? 52 : 40,
              height: isTV ? 52 : 40,
              decoration: BoxDecoration(
                color: focused ? colorGlassStrong : colorGlass,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: focused ? colorLineStrong : colorLine,
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                color: focused ? colorInk : colorInk2,
                size: isTV ? 24 : 18,
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  Widget _buildProfileBadge(bool isTV, {FocusOrder? focusOrder}) {
    if (_activeProfile == null) return const SizedBox.shrink();

    final gradIndex = _activeProfile!['gradientIndex'] as int? ?? 0;
    final colors = avatarGradients[gradIndex % avatarGradients.length];

    Widget child = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _isManualSelection = false;
          _startSlideshow();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          setState(() => _showDropdownMenu = !_showDropdownMenu);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => setState(() => _showDropdownMenu = !_showDropdownMenu),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: focused
                  ? (Matrix4.identity()..scale(1.04))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: isTV ? 14 : 10,
                vertical: isTV ? 7 : 5,
              ),
              decoration: BoxDecoration(
                color: focused ? colorSurface2 : colorSurface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: focused ? colorBrandB : colorLine,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isTV ? 30 : 24,
                    height: isTV ? 30 : 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _activeProfile!['avatar'] as String? ?? 'A',
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isTV ? 14 : 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _activeProfile!['name'] as String? ?? 'Invitado',
                    style: GoogleFonts.outfit(
                      color: colorInk,
                      fontWeight: FontWeight.w600,
                      fontSize: isTV ? 14 : 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorInk3,
                    size: isTV ? 18 : 14,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  // Drodown profile switching / managing menu
  Widget _buildProfileDropdownMenu(bool isTV) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161622).withOpacity(0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorLineStrong, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 40,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  '¿QUIÉN ESTÁ VIENDO?',
                  style: GoogleFonts.outfit(
                    color: colorInk3,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Profiles List inside dropdown
              ..._profiles.map((p) {
                final isCurrent = p['id'] == _activeProfile?['id'];
                final gradIndex = p['gradientIndex'] as int? ?? 0;
                final colors =
                    avatarGradients[gradIndex % avatarGradients.length];

                return _buildProfileDropdownItem(
                  name: p['name'] as String,
                  avatar: p['avatar'] as String,
                  colors: colors,
                  isCurrent: isCurrent,
                  onTap: () => _selectProfile(p),
                  onDelete: _profiles.length > 1
                      ? () => _deleteProfile(p)
                      : null,
                );
              }).toList(),

              const Divider(color: colorLine, height: 16),

              // Switch/manage actions
              _buildDropdownActionItem(
                label: 'Cambiar Perfil',
                icon: Icons.swap_horiz_rounded,
                onTap: () {
                  setState(() {
                    _showProfileSelector = true;
                    _showDropdownMenu = false;
                  });
                },
              ),
              _buildDropdownActionItem(
                label: 'Agregar Perfil',
                icon: Icons.add_circle_outline_rounded,
                onTap: () {
                  setState(() => _showDropdownMenu = false);
                  _showAddProfileDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDropdownItem({
    required String name,
    required String avatar,
    required List<Color> colors,
    required bool isCurrent,
    required VoidCallback onTap,
    required VoidCallback? onDelete,
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
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: focused ? colorSurface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      avatar,
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.outfit(
                        color: isCurrent ? colorInk : colorInk2,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Active indicator or delete option
                  if (isCurrent)
                    Icon(Icons.check_rounded, color: colorBrandA, size: 16)
                  else if (onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onDelete,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDropdownActionItem({
    required String label,
    required IconData icon,
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
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: focused ? colorSurface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, color: colorInk3, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: colorInk2,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Interactive cinematic hero panel
  Widget _buildHeroBillboard(bool isTV) {
    if (_focusedTitle.isEmpty) return const SizedBox.shrink();
    final tvScale = _tvScale(context);

    // Calculate how many movies we can paginate through (up to 5)
    final numDots = _recentMovies.length.clamp(0, 5);
    final isSeries = _focusedType == 'tvseries';
    final tagText = isSeries ? 'TOP 1 EN SERIES' : 'DESTACADO DE HOY';
    final posterUrl =
        (_focusedItemData?['poster_url'] ??
                _focusedItemData?['thumbnail_url'] ??
                _focusedItemData?['image_url'] ??
                _focusedBackdropUrl)
            .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: isTV ? 980 * tvScale : 720),
          padding: EdgeInsets.fromLTRB(
            isTV ? 22 * tvScale : 18,
            isTV ? 18 * tvScale : 14,
            isTV ? 22 * tvScale : 18,
            isTV ? 18 * tvScale : 14,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorGlassStrong.withOpacity(0.88),
                colorGlass.withOpacity(0.72),
                Colors.black.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: colorLineStrong, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: colorCrimson.withOpacity(0.16),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Text details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTV ? 10 * tvScale : 10,
                            vertical: isTV ? 5 * tvScale : 5,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [colorCrimson, colorFire],
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tagText.toUpperCase(),
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: isTV ? 10.5 * tvScale : 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isTV ? 10 * tvScale : 12),
                    Text(
                      _focusedTitle,
                      style: GoogleFonts.bebasNeue(
                        color: colorInk,
                        fontSize: isTV ? 62 * tvScale : 34,
                        height: 0.94,
                        letterSpacing: 0.4,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            offset: Offset(0, 6),
                            blurRadius: 26,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isTV ? 10 * tvScale : 12),
                    Wrap(
                      spacing: isTV ? 8 * tvScale : 8,
                      runSpacing: 8,
                      children: [
                        _buildHeroMetaPill('★ $_focusedRating'),
                        _buildHeroMetaPill(_focusedYear),
                        _buildHeroMetaPill('16+'),
                        _buildHeroMetaPill(_focusedDuration),
                        _buildHeroMetaPill(_focusedGenres),
                      ],
                    ),
                    SizedBox(height: isTV ? 14 * tvScale : 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTV ? 620 * tvScale : 640,
                      ),
                      child: Text(
                        _focusedDesc,
                        style: GoogleFonts.dmSans(
                          color: colorInk2,
                          fontSize: isTV ? 15 * tvScale : 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: isTV ? 3 : 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: isTV ? 16 * tvScale : 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            _buildHeroActionButton(
                              label: 'Reproducir',
                              icon: Icons.play_arrow_rounded,
                              isPrimary: true,
                              isTV: isTV,
                              onPressed: () {
                                _navigateToDetails(
                                  _focusedId,
                                  _focusedType,
                                  _focusedTitle,
                                  posterUrl,
                                );
                              },
                            ),
                            SizedBox(width: isTV ? 10 * tvScale : 12),
                            _buildHeroActionButton(
                              label: 'Más información',
                              icon: Icons.info_outline_rounded,
                              isPrimary: false,
                              isTV: isTV,
                              onPressed: () {
                                _navigateToDetails(
                                  _focusedId,
                                  _focusedType,
                                  _focusedTitle,
                                  posterUrl,
                                );
                              },
                            ),
                            SizedBox(width: isTV ? 10 * tvScale : 12),
                            _buildCircleIconButton(
                              icon: _isFocusedInMyList()
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                              isTV: isTV,
                              onPressed: _toggleFocusedMyList,
                            ),
                          ],
                        ),
                        if (numDots > 1 && !isTV)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(numDots, (index) {
                                final isActive = _currentSlideIndex == index;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(left: 6),
                                  width: isActive ? 34 : 12,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.white
                                        : colorInk3.withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Right Column: Gorgeous Poster Image of the Featured Item
              if (posterUrl.isNotEmpty) ...[
                SizedBox(width: isTV ? 28 * tvScale : 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: isTV ? 140 * tvScale : 90,
                      height: isTV ? 210 * tvScale : 135,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorLineStrong, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth:
                              ((isTV ? 140 * tvScale : 90) *
                                      MediaQuery.of(context).devicePixelRatio)
                                  .round(),
                          memCacheHeight:
                              ((isTV ? 210 * tvScale : 135) *
                                      MediaQuery.of(context).devicePixelRatio)
                                  .round(),
                          errorWidget: (context, url, error) => Container(
                            color: colorBg2,
                            child: const Icon(Icons.movie, color: colorInk3),
                          ),
                        ),
                      ),
                    ),
                    if (isTV && numDots > 1) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(numDots, (index) {
                          final isActive = _currentSlideIndex == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isActive ? 24 : 8,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? colorBrandA
                                  : colorInk3.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroMetaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.dmSans(
          color: colorInk,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCircleIconButton({
    required IconData icon,
    required bool isTV,
    required VoidCallback onPressed,
  }) {
    final tvScale = _tvScale(context);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: isTV ? 44 * tvScale : 40,
              height: isTV ? 44 * tvScale : 40,
              decoration: BoxDecoration(
                color: focused ? colorSurface2 : colorSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: focused ? colorCrimsonSoft : colorLineStrong,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: isTV ? 18 * tvScale : 18,
              ),
            ),
          );
        },
      ),
    );
  }

  // Frosted-glass modular Explore Categories grid selector
  Widget _buildCategoryHub(bool isTV) {
    final movieCount = _recentMovies.length;
    final seriesCount = _recentSeries.length;
    final animeCount = _animePicks.length;
    final tvScale = _tvScale(context);

    final categories = [
      {
        'title': 'Películas',
        'icon': Icons.movie_outlined,
        'subtitle': '$movieCount disponibles',
        'accent': accentPeliculas,
        'onTap': () => _navigateToPage(
          const HomeScreen(apiEndpoint: 'movies', title: 'Peliculas'),
        ),
      },
      {
        'title': 'Series',
        'icon': Icons.tv_outlined,
        'subtitle': '$seriesCount disponibles',
        'accent': accentSeries,
        'onTap': () => _navigateToPage(
          const HomeScreen(apiEndpoint: 'tvseries', title: 'Series'),
        ),
      },
      {
        'title': 'Anime',
        'icon': Icons.animation_sharp,
        'subtitle': '$animeCount seleccionadas',
        'accent': accentAnime,
        'onTap': () => _navigateToPage(
          const HomeScreen(
            apiEndpoint: 'tvseries',
            title: 'Anime',
            initialCategory: SeriesCategory.anime,
          ),
        ),
      },
      {
        'title': 'Telenovelas',
        'icon': Icons.favorite_border_rounded,
        'subtitle': 'coleccion',
        'accent': accentTelenovelas,
        'onTap': () => _navigateToPage(
          const HomeScreen(
            apiEndpoint: 'tvseries',
            title: 'Telenovelas',
            initialCategory: SeriesCategory.novelas,
          ),
        ),
      },
    ];
    _ensureCategoryFocusNodes(categories.length);

    if (isTV) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Explorar categorías',
                style: GoogleFonts.bebasNeue(
                  color: colorInk,
                  fontSize: 30 * tvScale,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${categories.length} módulos disponibles',
                style: GoogleFonts.dmSans(
                  color: colorInk3,
                  fontSize: 12 * tvScale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 14 * tvScale),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const crossAxisCount = 4; // Adjust to 4 since we removed 3 items
              final spacing =
                  16.0 * tvScale; // Increased spacing for premium look
              final tileWidth =
                  (width - ((crossAxisCount - 1) * spacing)) / crossAxisCount;
              final tileHeight =
                  tileWidth * 0.60; // Slightly shorter for cinematic look
              final ratio = tileWidth / tileHeight;

              return FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categories.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: ratio,
                  ),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    return _buildGlassHubCard(
                      title: cat['title'] as String,
                      subtitle: cat['subtitle'] as String,
                      icon: cat['icon'] as IconData,
                      accentColor: cat['accent'] as Color,
                      onTap: cat['onTap'] as VoidCallback,
                      isTV: true,
                      focusNode: _categoryFocusNodes[index],
                      autofocus: index == 0,
                      focusOrder: NumericFocusOrder(index.toDouble()),
                      onDirectionalKey: (key) => _handleCategoryDirectionalKey(
                        index: index,
                        count: categories.length,
                        columns: crossAxisCount,
                        key: key,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explorar categorías',
          style: GoogleFonts.bebasNeue(
            color: colorInk,
            fontSize: 28,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 170, // Increased size for a more premium look
                  height: 110,
                  child: _buildGlassHubCard(
                    title: cat['title'] as String,
                    subtitle: cat['subtitle'] as String,
                    icon: cat['icon'] as IconData,
                    accentColor: cat['accent'] as Color,
                    onTap: cat['onTap'] as VoidCallback,
                    isTV: false,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassHubCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    required bool isTV,
    FocusNode? focusNode,
    FocusOrder? focusOrder,
    bool autofocus = false,
    KeyEventResult Function(LogicalKeyboardKey key)? onDirectionalKey,
  }) {
    Widget child = Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _isManualSelection = false;
          _startSlideshow();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (onDirectionalKey != null) {
            final directionalResult = onDirectionalKey(event.logicalKey);
            if (directionalResult == KeyEventResult.handled) {
              return directionalResult;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              transform: focused
                  ? (Matrix4.identity()..scale(1.05))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: focused ? Colors.white : colorLine.withOpacity(0.3),
                  width: focused ? 3.0 : 1.0,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 25,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    color: focused ? colorGlassStrong : colorGlass,
                    padding: EdgeInsets.symmetric(
                      horizontal: isTV ? 10 : 12,
                      vertical: isTV ? 10 : 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: isTV ? 38 : 38,
                              height: isTV ? 38 : 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.20),
                                  width: 1.0,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                icon,
                                color: Colors.white,
                                size: isTV ? 20 : 20,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isTV ? 4 : 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.dmSans(
                                color: colorInk,
                                fontSize: isTV ? 13.0 : 14,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: isTV ? 2 : 3),
                            Text(
                              subtitle,
                              style: GoogleFonts.dmSans(
                                color: colorInk3,
                                fontSize: isTV ? 10 : 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  KeyEventResult _handleCategoryDirectionalKey({
    required int index,
    required int count,
    required int columns,
    required LogicalKeyboardKey key,
  }) {
    int? nextIndex;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index % columns != 0) nextIndex = index - 1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if ((index % columns) != columns - 1 && index + 1 < count) {
        nextIndex = index + 1;
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (index - columns >= 0) nextIndex = index - columns;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < count) {
        nextIndex = index + columns;
      }
    }

    if (nextIndex != null &&
        nextIndex >= 0 &&
        nextIndex < _categoryFocusNodes.length) {
      _categoryFocusNodes[nextIndex].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isFocusedInMyList() {
    if (_focusedId.isEmpty) return false;
    return _myListItems.any((item) {
      final id = (item['movies_id'] ?? item['id'] ?? item['media_id'] ?? '')
          .toString();
      return id == _focusedId;
    });
  }

  Future<void> _toggleFocusedMyList() async {
    if (_focusedId.isEmpty || _activeProfile == null) return;
    final profileId = _activeProfile!['id'].toString();

    final item = _recentMovies.firstWhere(
      (m) => (m['movies_id'] ?? m['id'] ?? '').toString() == _focusedId,
      orElse: () => _recentSeries.firstWhere(
        (s) => (s['movies_id'] ?? s['id'] ?? '').toString() == _focusedId,
        orElse: () => null,
      ),
    );

    final payload =
        item ??
        {
          'id': _focusedId,
          'title': _focusedTitle,
          'poster_url': _focusedBackdropUrl,
          'description': _focusedDesc,
          'genre': _focusedGenres,
          'year': _focusedYear,
          'release_year': _focusedYear,
          'media_type': _focusedType,
        };

    await MyListService.toggleItem(
      profileId: profileId,
      itemData: payload,
      mediaType: _focusedType,
      mediaId: _focusedId,
    );

    final updatedList = await MyListService.getItems(profileId);
    setState(() {
      _myListItems = updatedList;
    });
  }

  void _buildThematicRows(List<dynamic> movies, List<dynamic> series) {
    _top10Mixed = [];
    final moviesCount = movies.length;
    final seriesCount = series.length;
    for (int i = 0; i < 5; i++) {
      if (i < moviesCount) _top10Mixed.add(movies[i]);
      if (i < seriesCount) _top10Mixed.add(series[i]);
    }

    _dramaSeries = series.where((s) {
      final genres = (s['genres'] as String? ?? '').toLowerCase();
      return genres.contains('drama') || genres.contains('telenovela');
    }).toList();
    if (_dramaSeries.isEmpty) {
      _dramaSeries = series.take(8).toList();
    }

    _animePicks = series.where((s) {
      final genres = (s['genres'] as String? ?? '').toLowerCase();
      return genres.contains('anime') ||
          genres.contains('animac') ||
          genres.contains('cartoon');
    }).toList();
    if (_animePicks.isEmpty) {
      _animePicks = series.skip(2).take(8).toList();
    }

    _classicsPicks = movies.skip(2).take(8).toList();
  }

  // Carrete "Continuar Viendo" with progress bars
  Widget _buildLandscapeRow({
    required String title,
    required List<dynamic> items,
    required bool isTV,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final tvScale = _tvScale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.bebasNeue(
            color: colorInk2,
            fontSize: isTV ? 24 : 18,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: isTV ? 178 * tvScale : 190,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final imageUrl =
                    item['poster_url'] ??
                    item['thumbnail_url'] ??
                    item['image_url'] ??
                    '';
                final name = item['title'] ?? item['tv_name'] ?? '';
                final itemId =
                    (item['media_id'] ?? item['videos_id'] ?? item['id'] ?? '')
                        .toString();
                final type = (item['media_type'] ?? 'movie').toString();

                final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;

                return Padding(
                  padding: EdgeInsets.only(right: isTV ? 10.0 * tvScale : 22.0),
                  child: _buildLandscapeCard(
                    name: name,
                    imageUrl: imageUrl,
                    itemId: itemId,
                    type: type,
                    progress: progress,
                    itemData: item,
                    isTV: isTV,
                    focusOrder: NumericFocusOrder(index.toDouble()),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeCard({
    required String name,
    required String imageUrl,
    required String itemId,
    required String type,
    required double progress,
    required dynamic itemData,
    required bool isTV,
    FocusOrder? focusOrder,
  }) {
    final tvScale = _tvScale(context);
    final cardWidth = isTV ? 224.0 * tvScale : 220.0;
    final cardHeight = isTV ? 126.0 * tvScale : 124.0;

    Widget child = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _slideshowTimer?.cancel();
          _isManualSelection = true;
          _updateFocusedItem(itemData, 'movie');
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _navigateToDetails(itemId, type, name, imageUrl);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _navigateToDetails(itemId, type, name, imageUrl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: focused
                  ? (Matrix4.identity()..scale(1.05))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              width: cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image and Progress Slider
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: focused ? Colors.white : colorLine,
                        width: focused ? 3.0 : 1.0,
                      ),
                      boxShadow: focused
                          ? [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.25),
                                blurRadius: 25,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        focused ? 11.5 : 13.0,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth:
                                (cardWidth *
                                        MediaQuery.of(context).devicePixelRatio)
                                    .round(),
                            memCacheHeight:
                                (cardHeight *
                                        MediaQuery.of(context).devicePixelRatio)
                                    .round(),
                            errorWidget: (c, u, e) => Container(
                              color: colorBg2,
                              child: const Icon(Icons.movie, color: colorInk3),
                            ),
                          ),

                          // Hover / Focus Play indicator
                          Positioned.fill(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 140),
                              opacity: focused ? 1.0 : 0.0,
                              child: Container(
                                color: Colors.black.withOpacity(0.35),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: colorBg,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Linear Progress bar
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 5,
                            child: Container(
                              color: Colors.white.withOpacity(0.18),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [colorBrandA, colorBrandB],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isTV ? 8 * tvScale : 10),

                  // Metadata titles in Outfit
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.dmSans(
                            color: colorInk,
                            fontWeight: FontWeight.w700,
                            fontSize: isTV ? 12.5 * tvScale : 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Quedan ${(35 * (1 - progress)).toInt()} min',
                          style: GoogleFonts.dmSans(
                            color: colorInk3,
                            fontSize: isTV ? 11 * tvScale : 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  // Carrete Movie / Series cards
  Widget _buildHorizontalRow({
    required String title,
    required List<dynamic> items,
    required String type,
    required bool isTV,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final tvScale = _tvScale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.bebasNeue(
            color: colorInk2,
            fontSize: isTV ? 24 : 18,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: isTV ? 248 * tvScale : 210,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final imageUrl =
                    item['poster_url'] ?? item['thumbnail_url'] ?? '';
                final name = item['title'] ?? item['tv_name'] ?? '';
                final itemId = (item['videos_id'] ?? item['id'] ?? '')
                    .toString();

                return Padding(
                  padding: EdgeInsets.only(right: isTV ? 10.0 * tvScale : 20.0),
                  child: _buildMovieCard(
                    name: name,
                    imageUrl: imageUrl,
                    itemId: itemId,
                    type: type,
                    itemData: item,
                    rank: index + 1,
                    isTV: isTV,
                    focusOrder: NumericFocusOrder(index.toDouble()),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMovieCard({
    required String name,
    required String imageUrl,
    required String itemId,
    required String type,
    required dynamic itemData,
    required int rank,
    required bool isTV,
    FocusOrder? focusOrder,
  }) {
    final tvScale = _tvScale(context);
    final width = isTV ? 150.0 * tvScale : 120.0;
    final height = isTV ? 220.0 * tvScale : 180.0;

    Widget child = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _slideshowTimer?.cancel();
          _isManualSelection = true;
          _updateFocusedItem(itemData, type);
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _navigateToDetails(itemId, type, name, imageUrl);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _navigateToDetails(itemId, type, name, imageUrl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: focused
                  ? (Matrix4.identity()..scale(1.05))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: focused ? Colors.white : colorLine,
                        width: focused ? 3.0 : 1.0,
                      ),
                      boxShadow: focused
                          ? [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.25),
                                blurRadius: 25,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        focused ? 11.5 : 13.0,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth:
                                      (width *
                                              MediaQuery.of(
                                                context,
                                              ).devicePixelRatio)
                                          .round(),
                                  memCacheHeight:
                                      (height *
                                              MediaQuery.of(
                                                context,
                                              ).devicePixelRatio)
                                          .round(),
                                  errorWidget: (c, u, e) => Container(
                                    color: colorBg2,
                                    child: const Icon(
                                      Icons.movie,
                                      color: colorInk3,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: colorBg2,
                                  child: const Icon(
                                    Icons.movie,
                                    color: colorInk3,
                                  ),
                                ),

                          // Rank float tag
                          if (isTV && rank <= 5)
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: colorLineStrong,
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  rank.toString(),
                                  style: GoogleFonts.dmSans(
                                    color: colorInk,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),

                          // NEW Tag
                          if (rank <= 2)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colorBrandB,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  'NUEVO',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 8.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isTV ? 6 * tvScale : 8),

                  // Text name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      name,
                      style: GoogleFonts.dmSans(
                        color: colorInk,
                        fontSize: isTV ? 11.5 * tvScale : 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (focusOrder != null) {
      child = FocusTraversalOrder(order: focusOrder, child: child);
    }
    return child;
  }

  Widget _buildFooterHint(bool isTV) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 20.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: colorSurface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: colorLine, width: 1),
            ),
            child: Text(
              '▲ ▼ ◀ ▶',
              style: GoogleFonts.outfit(
                color: colorInk2,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Navega con el control remoto',
            style: GoogleFonts.outfit(
              color: colorInk3,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: colorLineStrong,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: colorSurface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: colorLine, width: 1),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.outfit(
                color: colorInk2,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Seleccionar',
            style: GoogleFonts.outfit(
              color: colorInk3,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // GORGEOUS GLASSMORPHIC PROFILE SELECTOR SCREEN ("¿Quién está viendo?")
  Widget _buildProfileSelectorScreen(bool isTV) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Smooth dynamic background (Optimized texture memory)
          if (_focusedBackdropUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: CachedNetworkImage(
                  imageUrl: _focusedBackdropUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: isTV ? 960 : 640,
                ),
              ),
            ),

          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isTV ? 6.0 : 15.0,
                sigmaY: isTV ? 6.0 : 15.0,
              ),
              child: Container(
                color: Colors.black.withOpacity(isTV ? 0.92 : 0.85),
              ),
            ),
          ),

          // 2. Profile Selection Content Layout
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '¿Quién está viendo ahora?',
                    style: GoogleFonts.sora(
                      color: colorInk,
                      fontSize: isTV ? 40 : 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Selecciona o administra tu perfil premium de entretenimiento',
                    style: GoogleFonts.outfit(
                      color: colorInk3,
                      fontSize: isTV ? 16 : 13,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Profiles grid row
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: isTV ? 32 : 16,
                    runSpacing: 24,
                    children: [
                      // List Profiles
                      ..._profiles.map((p) {
                        final gradIndex = p['gradientIndex'] as int? ?? 0;
                        final colors =
                            avatarGradients[gradIndex % avatarGradients.length];

                        return _buildProfileCard(
                          name: p['name'] as String,
                          avatar: p['avatar'] as String,
                          colors: colors,
                          isTV: isTV,
                          onTap: () => _selectProfile(p),
                          onDelete: _profiles.length > 1
                              ? () => _deleteProfile(p)
                              : null,
                        );
                      }).toList(),

                      // "Add Profile" card if profiles count is < 6
                      if (_profiles.length < 6) _buildAddProfileCard(isTV),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Footer instruction
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorLine),
                        ),
                        child: Text(
                          '◀ ▶',
                          style: GoogleFonts.outfit(
                            color: colorInk2,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Navega y pulsa OK para seleccionar tu perfil',
                        style: GoogleFonts.outfit(
                          color: colorInk3,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required String name,
    required String avatar,
    required List<Color> colors,
    required bool isTV,
    required VoidCallback onTap,
    required VoidCallback? onDelete,
  }) {
    final size = isTV ? 140.0 : 96.0;

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
              duration: const Duration(milliseconds: 160),
              transform: focused
                  ? (Matrix4.identity()..scale(1.08))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      // Colored Gradient Profile avatar square
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: focused ? Colors.white : colorLineStrong,
                            width: focused ? 3.0 : 1.5,
                          ),
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: colors[0].withOpacity(0.4),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          avatar,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontSize: isTV ? 48 : 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Delete float button (only if not focused and has more than 1 profile)
                      if (onDelete != null && !isCurrentProfileGuest(name))
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: onDelete,
                            borderRadius: BorderRadius.circular(99),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Profile name
                  Text(
                    name,
                    style: GoogleFonts.outfit(
                      color: focused ? colorInk : colorInk2,
                      fontWeight: focused ? FontWeight.bold : FontWeight.w600,
                      fontSize: isTV ? 16 : 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool isCurrentProfileGuest(String name) {
    return name == 'Invitado';
  }

  Widget _buildAddProfileCard(bool isTV) {
    final size = isTV ? 140.0 : 96.0;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _showAddProfileDialog();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: _showAddProfileDialog,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: focused
                  ? (Matrix4.identity()..scale(1.08))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: focused ? colorSurface2 : colorSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: focused ? colorBrandB : colorLine,
                        width: focused ? 2.5 : 1.5,
                      ),
                      boxShadow: focused
                          ? [
                              BoxShadow(
                                color: colorBrandB.withOpacity(0.2),
                                blurRadius: 15,
                              ),
                            ]
                          : [],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add_rounded,
                      color: focused ? colorInk : colorInk3,
                      size: isTV ? 48 : 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Agregar Perfil',
                    style: GoogleFonts.outfit(
                      color: focused ? colorInk : colorInk2,
                      fontWeight: focused ? FontWeight.bold : FontWeight.w600,
                      fontSize: isTV ? 16 : 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDotSeparator() {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(color: colorInk3, shape: BoxShape.circle),
    );
  }

  Widget _buildHeroActionButton({
    required String label,
    required IconData icon,
    required bool isPrimary,
    required bool isTV,
    required VoidCallback onPressed,
  }) {
    final tvScale = _tvScale(context);
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _isManualSelection = false;
          _startSlideshow();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              transform: focused
                  ? (Matrix4.identity()..scale(1.05))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: isTV ? 22 * tvScale : 18,
                vertical: isTV ? 12 * tvScale : 11,
              ),
              decoration: BoxDecoration(
                gradient: isPrimary
                    ? const LinearGradient(colors: [colorCrimson, colorFire])
                    : null,
                color: isPrimary
                    ? null
                    : (focused ? colorGlassStrong : colorGlass),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPrimary
                      ? Colors.transparent
                      : (focused ? colorCrimsonSoft : colorLineStrong),
                  width: 1.2,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: isPrimary
                              ? colorCrimson.withOpacity(0.35)
                              : colorBrandA.withOpacity(0.24),
                          blurRadius: 18,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: isTV ? 19 * tvScale : 18,
                  ),
                  SizedBox(width: isTV ? 9 * tvScale : 11),
                  Text(
                    label,
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: isTV ? 15 * tvScale : 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _navigateToPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Future<void> _showQuickJoinWatchParty() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = (prefs.getString('argon_watch_party_name') ?? 'Invitado')
        .trim();
    final roomController = TextEditingController();
    String info = '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161622),
              title: const Text(
                'Unirse a sala',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entraras como: $savedName',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: roomController,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Codigo de sala',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: 'ABC123',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (info.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        info,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
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
                    final room = roomController.text
                        .toUpperCase()
                        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
                        .trim();
                    if (room.length < 4) {
                      setDialogState(() => info = 'Ingresa un codigo valido.');
                      return;
                    }
                    Navigator.pop(context);
                    _navigateToPage(
                      WatchPartyLobbyScreen(
                        session: WatchPartySession(
                          roomId: room,
                          peerName: savedName.isEmpty ? 'Invitado' : savedName,
                          isHost: false,
                        ),
                        videoUrl: '',
                        isDirect: false,
                        headers: const <String, String>{},
                        serverQueue: const <Map<String, dynamic>>[],
                        mediaTitle: 'Sala compartida',
                        mediaType: 'watch_party',
                        mediaId: room,
                        mediaPosterUrl: '',
                        playbackKey: 'watch_party:$room',
                        startPositionSeconds: 0,
                      ),
                    );
                  },
                  child: const Text('Entrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToDetails(
    String id,
    String type,
    String title,
    String posterUrl,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          id: id,
          type: type,
          itemData: {
            'title': title,
            'tv_name': title,
            'poster_url': posterUrl,
            'thumbnail_url': posterUrl,
          },
        ),
      ),
    ).then((_) {
      _loadProfilesAndData();
    });
  }
}
