import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import 'details_screen.dart';
import 'search_screen.dart';

enum SeriesCategory { all, series, anime, novelas, retro, docus }

class HomeScreen extends StatefulWidget {
  final String title;
  final String apiEndpoint;
  final SeriesCategory initialCategory;

  const HomeScreen({
    Key? key,
    required this.title,
    required this.apiEndpoint,
    this.initialCategory = SeriesCategory.all,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _resultsBridgeFocusNode = FocusNode(debugLabel: 'home-results-bridge');
  final TextEditingController _localSearchController = TextEditingController();
  List<dynamic> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _localQuery = '';
  String _sortMode = 'default';

  // Dynamic tweak settings for style
  String _accentName = 'Mono';
  bool _atmosphere = false;
  late AnimationController _auroraController;

  // Selected Category filter for TV Series
  late SeriesCategory _selectedCategory;

  // Color System matching Dashboard
  static const Color colorBg = Color(0xFF060606);
  static const Color colorBg2 = Color(0xFF0C0C0E);
  static const Color colorSurface = Color(0x12161618);
  static const Color colorSurface2 = Color(0xCC17171A);
  static const Color colorLine = Color(0x22FFFFFF);
  static const Color colorLineStrong = Color(0x42FFFFFF);
  static const Color colorInk = Color(0xFFF4F1EA);
  static const Color colorInk2 = Color(0xFFD2CDC4);
  static const Color colorInk3 = Color(0xFF8E877D);
  static const Color colorCrimson = Color(0xFFE63946);
  static const Color colorCrimsonSoft = Color(0xFFFF6B6B);
  static const Color colorFire = Color(0xFFF97316);

  Color get currentAccentColor {
    switch (_accentName) {
      case 'Arena':
        return const Color(0xFFF2C078);
      case 'Niebla':
        return const Color(0xFFB7D8EE);
      case 'Mono':
      default:
        return colorCrimsonSoft;
    }
  }

  Color get colorBrandA => currentAccentColor;
  Color get colorBrandB => _accentName == 'Mono' ? colorFire : currentAccentColor;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    
    _auroraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);

    _loadTweakPreferences();
    _fetchItems();
    _scrollController.addListener(_onScroll);
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

  @override
  void dispose() {
    _auroraController.dispose();
    _scrollController.dispose();
    _resultsBridgeFocusNode.dispose();
    _localSearchController.dispose();
    super.dispose();
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore && _hasMore) {
      _fetchMoreItems();
    }
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _page = 1;
      _hasMore = true;
    });

    try {
      List<dynamic> data;
      if (widget.apiEndpoint == 'movies') {
        data = await _apiClient.getMovies(page: _page);
      } else if (widget.apiEndpoint == 'tvseries') {
        data = await _apiClient.getTvSeries(page: _page);
      } else if (widget.apiEndpoint == 'live') {
        data = await _apiClient.getLiveTv();
        _hasMore = false;
      } else {
        data = [];
      }

      setState(() {
        _items = data;
        _isLoading = false;
        if (data.isEmpty) _hasMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _fetchMoreItems() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
      _page++;
    });

    try {
      List<dynamic> data;
      if (widget.apiEndpoint == 'movies') {
        data = await _apiClient.getMovies(page: _page);
      } else if (widget.apiEndpoint == 'tvseries') {
        data = await _apiClient.getTvSeries(page: _page);
      } else {
        data = [];
      }

      setState(() {
        if (data.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(data);
        }
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
        _page--;
      });
    }
  }

  SeriesCategory _classifySeries(dynamic item) {
    final title = (item['title'] ?? item['tv_name'] ?? '').toString().toLowerCase();
    final desc = (item['description'] ?? '').toString().toLowerCase();
    
    final animeKeywords = [
      'anime', 'manga', 'animación', 'animacion', 'japon', 'japón', 'fate/zero', 'avatar',
      'maestro', 'obsolete', 'caballero santo', 'gangsta', 'nodame', 'digimon', 'arjuna',
      'barom', 'kabaneri', 'nube', 'oban', 'bluey', 'valle salvaje', 'dora', 'paw patrol',
      'darkstalkers', 'pokemon', 'naruto', 'akane', 'súper once', 'super once', 'black lagoon',
      'violet evergarden', 'kenja', 'thundercats', 'momochi', 'gacha', 'noragami', 'akame',
      'tokyo revengers', 'code geass', 'link click', 'danmachi', 'stratos', 'voltron',
      'sensou', 'dante', 'leyendas', 'rey inmortal', 'initial d', 'kotaro', 'órbita',
      'leveling', 'shippuden', 'one piece', 'shingeki', 'titan', 'demon slayer', 'kimetsu',
      'jujutsu', 'kaisen', 'my hero', 'academia', 'death note', 'evangelion', 'bleach',
      'black clover', 'chainsaw', 'baki', 'yugioh', 'bakugan', 'beyblade', 'saint seiya',
      'caballeros del zodiaco', 'sailor moon', 'inuyasha', 'sword art', 'sao', 'tokyo ghoul',
      'hunter x', 'fairy tail', 'haikyuu', 'boruto'
    ];
    
    final novelaKeywords = [
      'novela', 'telenovela', 'escobar', 'patrón del mal', 'patron del mal', 'mariachi',
      'señor de los cielos', 'senor de los cielos', 'nuevo rico', 'nuevo pobre', 'carísima',
      'carisima', 'cartel de los sapos', 'alias jj', 'corazón', 'pasión', 'pasion', 'reina',
      'del sur', 'betty', 'fea', 'gavilanes', 'maría la del barrio', 'rubí', 'la usurpadora',
      'café con aroma', 'cafe con aroma', 'lo que la vida', 'cielo', 'señor de los', 'patrón',
      'sapos', 'sin senos', 'teresa', 'usurpadora', 'gata salvaje', 'doña bárbara', 'dona barbara',
      'amores verdaderos', 'tierra de reyes', 'mi camino es amarte', 'cabo', 'la madrastra',
      'telenovelas'
    ];

    final retroKeywords = [
      'retro', 'clásico', 'clasico', 'vintage', '80s', '90s', '70s', 'el chavo', 'chavo del 8',
      'chavo del ocho', 'alf', 'macgyver', 'la ley y el orden', 'los simpson', 'los simpsons',
      'seinfeld', 'friends', 'bonanza', 'mi bella genio', 'hechicera', 'superagente 86', 'a-team',
      'magníficos', 'magnificos', 'brigada a', 'corrupción en miami', 'miami vice', 'columbo',
      'perry mason', 'knight rider', 'auto fantástico', 'auto fantastico', 'looney tunes',
      'tom y jerry', 'pantera rosa', 'dinosaurios', 'family matters', 'cosby', 'el príncipe del rap',
      'principe del rap', 'fresh prince', 'full house', 'tres por tres', 'baywatch', 'guardianes de la bahía',
      'x-files', 'expedientes x', 'twin peaks'
    ];

    final docuKeywords = [
      'documental', 'docu', 'history', 'discovery', 'planeta', 'tierra', 'sobrevivir', 'crímenes',
      'crimenes', 'asesino', 'misterio', 'investigación', 'investigacion', 'reality', 'desafío',
      'desafio', 'natgeo', 'national geographic', 'animal planet', 'ciencia', 'espacio', 'cosmos',
      'nasa', 'guerra mundial', 'historia', 'biografía', 'biografia', 'vida salvaje', 'océano',
      'oceano', 'naturaleza', 'dinosaurio', 'alienígenas', 'aliens ancestrales'
    ];
    
    for (var kw in animeKeywords) {
      if (title.contains(kw) || desc.contains(kw)) {
        return SeriesCategory.anime;
      }
    }
    
    for (var kw in novelaKeywords) {
      if (title.contains(kw) || desc.contains(kw)) {
        return SeriesCategory.novelas;
      }
    }

    for (var kw in retroKeywords) {
      if (title.contains(kw) || desc.contains(kw)) {
        return SeriesCategory.retro;
      }
    }

    for (var kw in docuKeywords) {
      if (title.contains(kw) || desc.contains(kw)) {
        return SeriesCategory.docus;
      }
    }
    
    return SeriesCategory.series;
  }

  List<dynamic> get _filteredItems {
    List<dynamic> filtered = List<dynamic>.from(_items);

    if (widget.apiEndpoint == 'tvseries' && _selectedCategory != SeriesCategory.all) {
      filtered = filtered.where((item) {
        final cat = _classifySeries(item);
        return cat == _selectedCategory;
      }).toList();
    }

    final query = _localQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((item) {
        final title = (item['title'] ?? item['tv_name'] ?? item['channel_name'] ?? '').toString().toLowerCase();
        final desc = (item['description'] ?? '').toString().toLowerCase();
        final genre = (item['genre'] ?? '').toString().toLowerCase();
        return title.contains(query) || desc.contains(query) || genre.contains(query);
      }).toList();
    }

    if (_sortMode == 'az') {
      filtered.sort((a, b) {
        final at = (a['title'] ?? a['tv_name'] ?? a['channel_name'] ?? '').toString().toLowerCase();
        final bt = (b['title'] ?? b['tv_name'] ?? b['channel_name'] ?? '').toString().toLowerCase();
        return at.compareTo(bt);
      });
    } else if (_sortMode == 'year') {
      int toYear(dynamic item) {
        final raw = (item['year'] ?? item['release_year'] ?? item['release_date'] ?? '').toString();
        final m = RegExp(r'(19|20)\d{2}').firstMatch(raw);
        return int.tryParse(m?.group(0) ?? '') ?? 0;
      }
      filtered.sort((a, b) => toYear(b).compareTo(toYear(a)));
    } else if (_sortMode == 'rating') {
      double toRating(dynamic item) {
        final raw = (item['imdb_rating'] ?? item['rating'] ?? '').toString();
        return double.tryParse(raw.replaceAll(',', '.')) ?? 0.0;
      }
      filtered.sort((a, b) => toRating(b).compareTo(toRating(a)));
    }

    if (filtered.length < 8 && _hasMore && !_isLoadingMore && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchMoreItems();
      });
    }
    
    return filtered;
  }

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

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorBg2,
        body: Center(child: CircularProgressIndicator(color: colorBrandA)),
      );
    }

    final mediaWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = isTV
        ? (mediaWidth >= 1800
            ? 8
            : mediaWidth >= 1500
                ? 7
                : mediaWidth >= 1280
                    ? 6
                    : 5)
        : (mediaWidth > 600 ? 5 : 3);
    
    const double childAspectRatio = 0.68;

    final content = Column(
      children: [
        if (isTV) _buildTvToolbar(),
        if (widget.apiEndpoint == 'tvseries') _buildCategoryFilters(isTV),
        Expanded(
          child: _filteredItems.isEmpty && _isLoadingMore
              ? Center(child: CircularProgressIndicator(color: colorBrandA))
              : (_filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        'No hay resultados para este filtro.',
                        style: GoogleFonts.outfit(color: colorInk3, fontSize: 16),
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: isTV,
                      child: GridView.builder(
                        controller: _scrollController,
                        cacheExtent: isTV ? 2200 : 1200,
                        padding: EdgeInsets.symmetric(
                          horizontal: isTV ? (mediaWidth / 1920 * 18.0).clamp(12.0, 22.0) : 12.0,
                          vertical: isTV ? (mediaWidth / 1920 * 8.0).clamp(6.0, 12.0) : 20.0,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: childAspectRatio,
                          crossAxisSpacing: isTV ? (mediaWidth / 1920 * 10.0).clamp(8.0, 14.0) : 12,
                          mainAxisSpacing: isTV ? (mediaWidth / 1920 * 12.0).clamp(10.0, 16.0) : 16,
                        ),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          final imageUrl = item['poster_url'] ?? item['thumbnail_url'] ?? item['logo'] ?? '';
                          final name = item['title'] ?? item['tv_name'] ?? item['channel_name'] ?? '';
                          final itemId = item['movies_id']?.toString() ?? item['videos_id']?.toString() ?? item['live_tv_id']?.toString() ?? '';

                          return _FocusableCard(
                            isTV: isTV,
                            autofocus: index == 0,
                            imageUrl: imageUrl,
                            name: name,
                            itemId: itemId,
                            colorBrandA: colorBrandA,
                            colorLine: colorLine,
                            colorSurface: colorSurface,
                            colorSurface2: colorSurface2,
                            colorInk: colorInk,
                            colorInk2: colorInk2,
                            colorInk3: colorInk3,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DetailsScreen(
                                    itemData: item,
                                    type: widget.apiEndpoint,
                                    id: itemId,
                                  ),
                                ),
                              ).then((_) {
                                _loadTweakPreferences();
                              });
                            },
                          );
                        },
                      ),
                    )),
        ),
        if (_isLoadingMore && _filteredItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(color: colorBrandA)),
          ),
      ],
    );

    final mainContent = isTV
        ? FocusTraversalGroup(child: content)
        : RefreshIndicator(
            color: colorBrandA,
            onRefresh: _fetchItems,
            child: content,
          );

    return Scaffold(
      backgroundColor: colorBg2,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildAuroraBackground(),
          SafeArea(
            bottom: false,
            child: mainContent,
          ),
        ],
      ),
    );
  }

  Future<void> _openLocalSearchDialog() async {
    _localSearchController.text = _localQuery;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorSurface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Buscar en esta lista', style: GoogleFonts.sora(color: colorInk, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _localSearchController,
            autofocus: true,
            style: GoogleFonts.outfit(color: colorInk),
            decoration: InputDecoration(
              hintText: 'Ej: avengers, drama, anime...',
              hintStyle: GoogleFonts.outfit(color: colorInk3),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colorBrandA, width: 2),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text('Limpiar', style: GoogleFonts.outfit(color: colorBrandA, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: GoogleFonts.outfit(color: colorInk3)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _localSearchController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorBrandA,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Aplicar', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _localQuery = result.trim();
    });
  }

  Widget _buildTvToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: GoogleFonts.bebasNeue(
                        color: colorInk,
                        fontSize: 32,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_filteredItems.length} resultados',
                      style: GoogleFonts.outfit(color: colorInk3, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _toolbarButton(
                label: _localQuery.isEmpty ? 'Buscar en lista' : 'Filtro: $_localQuery',
                icon: Icons.search,
                onTap: _openLocalSearchDialog,
              ),
              const SizedBox(width: 8),
              _toolbarButton(
                label: 'Busqueda global',
                icon: Icons.travel_explore,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())).then((_) {
                    _loadTweakPreferences();
                  });
                },
              ),
              const SizedBox(width: 8),
              _toolbarButton(
                label: 'Actualizar',
                icon: Icons.refresh,
                onTap: _fetchItems,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _sortChip('Relevante', 'default'),
              const SizedBox(width: 8),
              _sortChip('A-Z', 'az'),
              const SizedBox(width: 8),
              _sortChip('Año', 'year'),
              const SizedBox(width: 8),
              _sortChip('Rating', 'rating'),
              if (_localQuery.isNotEmpty) ...[
                const SizedBox(width: 12),
                _toolbarButton(
                  label: 'Quitar filtro',
                  icon: Icons.close,
                  onTap: () {
                    setState(() {
                      _localQuery = '';
                    });
                  },
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
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
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: focused ? colorSurface2 : colorSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? colorBrandA : colorLine,
                  width: focused ? 2.0 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortChip(String label, String mode) {
    final selected = _sortMode == mode;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
          setState(() {
            _sortMode = mode;
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              setState(() {
                _sortMode = mode;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? colorBrandA : (focused ? colorSurface2 : colorSurface),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: focused ? colorBrandA : colorLine,
                  width: focused ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  color: (selected || focused) ? Colors.black : colorInk2,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryFilters(bool isTV) {
    final filters = [
      {'label': 'TODAS', 'category': SeriesCategory.all},
      {'label': 'SERIES', 'category': SeriesCategory.series},
      {'label': 'ANIME', 'category': SeriesCategory.anime},
      {'label': 'TELENOVELAS', 'category': SeriesCategory.novelas},
      {'label': 'RETRO', 'category': SeriesCategory.retro},
      {'label': 'DOCUMENTALES', 'category': SeriesCategory.docus},
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTV ? 18.0 : 12.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isSelected = _selectedCategory == f['category'];
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select)) {
                    setState(() {
                      _selectedCategory = f['category'] as SeriesCategory;
                    });
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = f['category'] as SeriesCategory;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? colorBrandA 
                              : (focused ? colorSurface2 : colorSurface),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: focused ? colorBrandA : colorLine,
                            width: focused ? 1.5 : 1.0,
                          ),
                        ),
                        child: Text(
                          f['label'] as String,
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.black : (focused ? Colors.white : colorInk3),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FocusableCard extends StatefulWidget {
  final bool isTV;
  final bool autofocus;
  final String imageUrl;
  final String name;
  final String itemId;
  final Color colorBrandA;
  final Color colorLine;
  final Color colorSurface;
  final Color colorSurface2;
  final Color colorInk;
  final Color colorInk2;
  final Color colorInk3;
  final VoidCallback onTap;

  const _FocusableCard({
    required this.isTV,
    required this.autofocus,
    required this.imageUrl,
    required this.name,
    required this.itemId,
    required this.colorBrandA,
    required this.colorLine,
    required this.colorSurface,
    required this.colorSurface2,
    required this.colorInk,
    required this.colorInk2,
    required this.colorInk3,
    required this.onTap,
  });

  @override
  State<_FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<_FocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusableActionDetector(
        onShowFocusHighlight: (hasFocus) {
          if (_isFocused != hasFocus) {
            setState(() => _isFocused = hasFocus);
          }
          if (hasFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.45,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: RepaintBoundary(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              transform: _isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isFocused ? widget.colorBrandA : widget.colorLine,
                  width: _isFocused ? 2.5 : 1.0,
                ),
                boxShadow: [
                  if (_isFocused)
                    BoxShadow(
                      color: widget.colorBrandA.withOpacity(0.35),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      filterQuality: FilterQuality.medium,
                      memCacheWidth: widget.isTV ? 260 : 240,
                      placeholder: (context, url) => Container(color: widget.colorSurface),
                      errorWidget: (context, url, error) => Container(
                        color: widget.colorSurface2,
                        child: Icon(Icons.movie, color: widget.colorInk3),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.0),
                              Colors.black.withOpacity(_isFocused ? 0.90 : 0.78),
                            ],
                          ),
                        ),
                        child: const SizedBox(height: 60),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        child: Text(
                          widget.name,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
