import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/tv_focusable_item.dart';
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
          : RefreshIndicator(
              color: Colors.purpleAccent,
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(isTV ? 24 : 12, isTV ? 24 : 12, isTV ? 24 : 12, 24),
                children: [
                  Text(
                    'Inicio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTV ? 34 : 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _quickActions(isTV),
                  const SizedBox(height: 18),
                  _rowSection('Tendencias en Peliculas', _movies, isTV, defaultType: 'movies'),
                  const SizedBox(height: 18),
                  _rowSection('Series destacadas', _series, isTV, defaultType: 'tvseries'),
                  const SizedBox(height: 18),
                  _rowSection('Canales en vivo', _live, isTV, defaultType: 'live'),
                ],
              ),
            ),
    );
  }

  Widget _quickActions(bool isTV) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _actionChip('Peliculas', Icons.movie, () => widget.onOpenSection?.call(1), isTV),
        _actionChip('Series', Icons.tv, () => widget.onOpenSection?.call(2), isTV),
        _actionChip('En Vivo', Icons.live_tv, () => widget.onOpenSection?.call(3), isTV),
        _actionChip('Buscar', Icons.search, () => widget.onOpenSection?.call(4), isTV),
        _actionChip('Errores', Icons.bug_report, () => widget.onOpenSection?.call(5), isTV),
      ],
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap, bool isTV) {
    return TvFocusableItem(
      onPressed: onTap,
      focusColor: Colors.purpleAccent,
      borderRadius: BorderRadius.circular(12),
      scaleOnFocus: 1.05,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isTV ? 16 : 12, vertical: isTV ? 12 : 10),
        decoration: BoxDecoration(
          color: Colors.white10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: isTV ? 20 : 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: isTV ? 16 : 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowSection(String title, List<dynamic> items, bool isTV, {required String defaultType}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: isTV ? 22 : 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: isTV ? 250 : 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return _DashboardCard(
                isTV: isTV,
                autofocus: index == 0,
                item: item,
                defaultType: defaultType,
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

  const _DashboardCard({
    required this.isTV,
    required this.autofocus,
    required this.item,
    required this.defaultType,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _focused = false;

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

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.item['poster_url'] ??
        widget.item['thumbnail_url'] ??
        widget.item['logo'] ??
        widget.item['image_url'] ??
        '';
    final title = widget.item['title'] ?? widget.item['tv_name'] ?? widget.item['channel_name'] ?? 'Contenido';

    return TvFocusableItem(
      autofocus: widget.autofocus,
      onPressed: () => _openDetails(context),
      focusColor: Colors.purpleAccent,
      borderRadius: BorderRadius.circular(12),
      scaleOnFocus: 1.05,
      child: SizedBox(
        width: widget.isTV ? 165 : 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              memCacheWidth: widget.isTV ? 420 : 240,
              placeholder: (context, url) => Container(color: Colors.grey[900]),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[850],
                child: const Icon(Icons.movie, color: Colors.white54),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withOpacity(0.7),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.isTV ? 13 : 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
}
