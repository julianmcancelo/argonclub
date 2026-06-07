import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/tv_focusable_item.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/hero_banner.dart';
import '../api/api_client.dart';
import 'details_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  final ValueChanged<int>? onOpenSection;

  const HomeDashboardScreen({Key? key, this.onOpenSection}) : super(key: key);

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _loading = true;
  List<dynamic> _movies = [];
  List<dynamic> _series = [];
  List<dynamic> _live = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _apiClient.getMovies(page: 1),
        _apiClient.getTvSeries(page: 1),
        _apiClient.getLiveTv(),
      ]);
      if (!mounted) return;
      setState(() {
        _movies = (results[0] as List).take(18).toList();
        _series = (results[1] as List).take(18).toList();
        _live = (results[2] as List).take(18).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);
    final bgColor = const Color(0xFF0F0F0F);

    return Scaffold(
      backgroundColor: bgColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Row(
              children: [
                // Navigation Sidebar
                SidebarNav(
                  selectedIndex: 0,
                  onMenuSelected: (id) {
                    if (id == 0) return; // Already here
                    widget.onOpenSection?.call(id);
                  },
                ),
                // Main Content
                Expanded(
                  child: RefreshIndicator(
                    color: Colors.white,
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hero Banner
                          if (_movies.isNotEmpty)
                            HeroBanner(
                              item: _movies.first,
                              isTV: isTV,
                              type: 'movies',
                            ),
                          
                          // Carousels
                          Padding(
                            padding: EdgeInsets.fromLTRB(isTV ? 48 : 24, 0, 0, 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _rowSection(
                                  'Tendencias en Películas',
                                  _movies.length > 1 ? _movies.sublist(1) : _movies,
                                  isTV,
                                  defaultType: 'movies',
                                  isLiveTv: false,
                                ),
                                const SizedBox(height: 32),
                                _rowSection(
                                  'Series Destacadas',
                                  _series,
                                  isTV,
                                  defaultType: 'tvseries',
                                  isLiveTv: false,
                                ),
                                const SizedBox(height: 32),
                                _rowSection(
                                  'Canales en Vivo',
                                  _live,
                                  isTV,
                                  defaultType: 'live',
                                  isLiveTv: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _rowSection(String title, List<dynamic> items, bool isTV, {required String defaultType, required bool isLiveTv}) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    // Height changes based on aspect ratio: 2:3 for movies/series, 16:9 for Live TV
    final double cardHeight = isLiveTv ? (isTV ? 160 : 120) : (isTV ? 300 : 210);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: isTV ? 24 : 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              return _DashboardCard(
                isTV: isTV,
                autofocus: false, // We don't autofocus the first item anymore because sidebar takes focus initially
                item: item,
                defaultType: defaultType,
                isLiveTv: isLiveTv,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatefulWidget {
  final bool isTV;
  final bool autofocus;
  final dynamic item;
  final String defaultType;
  final bool isLiveTv;

  const _DashboardCard({
    required this.isTV,
    required this.autofocus,
    required this.item,
    required this.defaultType,
    required this.isLiveTv,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _isFocused = false;

  String _resolveType(dynamic item) {
    final isTv = item['is_tvseries'] == '1' || item['tv_name'] != null;
    final isLive = item['stream_url'] != null || item['channel_name'] != null || item['live_tv_id'] != null;
    if (isLive) return 'live';
    if (isTv) return 'tvseries';
    return widget.defaultType;
  }

  String _resolveId(dynamic item) {
    return item['movies_id']?.toString() ??
        item['videos_id']?.toString() ??
        item['live_tv_id']?.toString() ??
        '';
  }

  void _openDetails(BuildContext context) {
    final id = _resolveId(widget.item);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          itemData: widget.item,
          type: _resolveType(widget.item),
          id: id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.item['poster_url'] ??
        widget.item['thumbnail_url'] ??
        widget.item['logo'] ??
        widget.item['image_url'] ??
        '';
    final title = widget.item['title'] ?? widget.item['tv_name'] ?? widget.item['channel_name'] ?? 'Contenido';

    // Width calculations
    final double cardHeight = widget.isLiveTv ? (widget.isTV ? 160 : 120) : (widget.isTV ? 300 : 210);
    final double cardWidth = widget.isLiveTv ? (cardHeight * 16 / 9) : (cardHeight * 2 / 3);

    return TvFocusableItem(
      autofocus: widget.autofocus,
      onPressed: () => _openDetails(context),
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      focusColor: Colors.transparent, // Disable default focus color to use custom border
      scaleOnFocus: 1.05,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                memCacheWidth: widget.isLiveTv ? 400 : 300,
                placeholder: (context, url) => Container(color: Colors.grey[900]),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[850],
                  child: const Icon(Icons.movie, color: Colors.white54),
                ),
              ),
            ),
            // Title overlay (always show for Live TV, show on focus for Movies/Series if needed, 
            // but usually modern UIs omit it for posters unless it's highlighted)
            if (widget.isLiveTv || _isFocused)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(9),
                      bottomRight: Radius.circular(9),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: widget.isTV ? 14 : 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
