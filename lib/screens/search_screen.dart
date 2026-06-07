import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search-input');
  final FocusNode _resultsBridgeFocusNode = FocusNode(debugLabel: 'search-results-bridge');
  late final List<FocusNode> _filterFocusNodes;

  List<dynamic> _items = [];
  List<dynamic> _allItems = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _currentQuery = '';
  String _typeFilter = 'all';
  String _franchiseFilter = 'all';

  @override
  void initState() {
    super.initState();
    _filterFocusNodes = List.generate(7, (index) => FocusNode(debugLabel: 'search-filter-$index'));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _resultsBridgeFocusNode.dispose();
    for (final node in _filterFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMoreItems();
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _currentQuery = query;
      _isLoading = true;
      _page = 1;
      _hasMore = true;
      _items = [];
      _allItems = [];
    });

    try {
      var data = await _apiClient.search(_currentQuery, page: _page);
      if (data.isEmpty) {
        data = await _apiClient.searchLocalFallback(_currentQuery);
      }

      setState(() {
        _allItems = data;
        _items = _applyFilters(_allItems);
        _isLoading = false;
        if (data.isEmpty) _hasMore = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _fetchMoreItems() async {
    if (!_hasMore || _currentQuery.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
      _page++;
    });

    try {
      final data = await _apiClient.search(_currentQuery, page: _page);
      setState(() {
        _allItems.addAll(data);
        _items = _applyFilters(_allItems);
        if (data.isEmpty) _hasMore = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
        _page--;
      });
    }
  }

  List<dynamic> _applyFilters(List<dynamic> input) {
    bool isTv(dynamic item) => item['is_tvseries'] == '1' || item['tv_name'] != null;
    bool isLive(dynamic item) =>
        item['stream_url'] != null || item['channel_name'] != null || item['live_tv_id'] != null;
    bool isMovie(dynamic item) => !isTv(item) && !isLive(item);

    bool matchesType(dynamic item) {
      switch (_typeFilter) {
        case 'movies':
          return isMovie(item);
        case 'tvseries':
          return isTv(item);
        case 'live':
          return isLive(item);
        default:
          return true;
      }
    }

    bool matchesFranchise(dynamic item) {
      if (_franchiseFilter == 'all') return true;
      final blob = [item['title'], item['tv_name'], item['description'], item['genre']].join(' ').toLowerCase();
      if (_franchiseFilter == 'marvel') return blob.contains('marvel') || blob.contains('avengers');
      if (_franchiseFilter == 'dc') {
        return blob.contains(' dc ') || blob.contains('batman') || blob.contains('superman');
      }
      return true;
    }

    return input.where((item) => matchesType(item) && matchesFranchise(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: TextField(
          focusNode: _searchFocusNode,
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Buscar peliculas, series...',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onSubmitted: _performSearch,
          textInputAction: TextInputAction.search,
          autofocus: isTV,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.red),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      ),
      body: Focus(
        onKeyEvent: (node, event) {
          if (!isTV || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowDown && _searchFocusNode.hasFocus) {
            _moveFromSearchToResults();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _buildBody(isTV),
      ),
    );
  }

  Widget _buildBody(bool isTV) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    if (_items.isEmpty && _currentQuery.isNotEmpty) {
      return const Center(child: Text('No se encontraron resultados.', style: TextStyle(color: Colors.white)));
    }

    if (_items.isEmpty) {
      return const Center(child: Text('Escribe algo para buscar...', style: TextStyle(color: Colors.white54)));
    }

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              _chip('Todo', _typeFilter == 'all', () {
                _typeFilter = 'all';
              }, focusNode: _filterFocusNodes[0]),
              const SizedBox(width: 8),
              _chip('Peliculas', _typeFilter == 'movies', () {
                _typeFilter = 'movies';
              }, focusNode: _filterFocusNodes[1]),
              const SizedBox(width: 8),
              _chip('Series', _typeFilter == 'tvseries', () {
                _typeFilter = 'tvseries';
              }, focusNode: _filterFocusNodes[2]),
              const SizedBox(width: 8),
              _chip('En Vivo', _typeFilter == 'live', () {
                _typeFilter = 'live';
              }, focusNode: _filterFocusNodes[3]),
              const SizedBox(width: 14),
              _chip('Franquicia: Todas', _franchiseFilter == 'all', () {
                _franchiseFilter = 'all';
              }, focusNode: _filterFocusNodes[4]),
              const SizedBox(width: 8),
              _chip('Marvel', _franchiseFilter == 'marvel', () {
                _franchiseFilter = 'marvel';
              }, focusNode: _filterFocusNodes[5]),
              const SizedBox(width: 8),
              _chip('DC', _franchiseFilter == 'dc', () {
                _franchiseFilter = 'dc';
              }, focusNode: _filterFocusNodes[6]),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            primary: false,
            controller: _scrollController,
            cacheExtent: isTV ? 2200 : 1200,
            padding: EdgeInsets.all(isTV ? 18 : 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isTV ? 6 : 3,
              childAspectRatio: isTV ? 0.62 : 0.7,
              crossAxisSpacing: isTV ? 14 : 8,
              mainAxisSpacing: isTV ? 14 : 8,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final imageUrl = item['poster_url'] ?? item['thumbnail_url'] ?? '';
              final name = item['title'] ?? item['tv_name'] ?? item['channel_name'] ?? '';
              final isTv = item['is_tvseries'] == '1' || item['tv_name'] != null;
              final isLive = item['stream_url'] != null || item['channel_name'] != null || item['live_tv_id'] != null;
              final type = isLive ? 'live' : (isTv ? 'tvseries' : 'movies');

              return _FocusableSearchCard(
                isTV: isTV,
                autofocus: index == 0,
                bridgeFocusNode: index == 0 ? _resultsBridgeFocusNode : null,
                imageUrl: imageUrl,
                name: name,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailsScreen(
                        itemData: item,
                        type: type,
                        id: item['movies_id']?.toString() ?? item['videos_id']?.toString() ?? '',
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator(color: Colors.red)),
          ),
      ],
    );
  }

  void _moveFromSearchToResults() {
    for (final node in _filterFocusNodes) {
      if (node.context != null) {
        node.requestFocus();
        return;
      }
    }

    if (_resultsBridgeFocusNode.context != null) {
      _resultsBridgeFocusNode.requestFocus();
      return;
    }

    _searchFocusNode.focusInDirection(TraversalDirection.down);
  }

  Widget _chip(String label, bool selected, VoidCallback setter, {FocusNode? focusNode}) {
    return ChoiceChip(
      focusNode: focusNode,
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          setter();
          _items = _applyFilters(_allItems);
        });
      },
    );
  }
}

class _FocusableSearchCard extends StatefulWidget {
  final bool isTV;
  final bool autofocus;
  final FocusNode? bridgeFocusNode;
  final String imageUrl;
  final String name;
  final VoidCallback onTap;

  const _FocusableSearchCard({
    required this.isTV,
    required this.autofocus,
    this.bridgeFocusNode,
    required this.imageUrl,
    required this.name,
    required this.onTap,
  });

  @override
  State<_FocusableSearchCard> createState() => _FocusableSearchCardState();
}

class _FocusableSearchCardState extends State<_FocusableSearchCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.bridgeFocusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (_focused != value) {
            setState(() => _focused = value);
          }
          if (value) {
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
              duration: const Duration(milliseconds: 120),
              transform: _focused ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: _focused ? Border.all(color: Colors.red, width: 3) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                  CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    filterQuality: FilterQuality.medium,
                    memCacheWidth: widget.isTV ? 420 : 240,
                    memCacheHeight: widget.isTV ? 1080 : 720,
                    placeholder: (context, url) => Container(color: Colors.grey[900]),
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.grey[800], child: const Icon(Icons.movie, color: Colors.white54)),
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
                            Colors.black.withOpacity(_focused ? 0.86 : 0.74),
                          ],
                        ),
                      ),
                      padding: EdgeInsets.symmetric(vertical: widget.isTV ? 8 : 4, horizontal: 4),
                      child: Text(
                        widget.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.isTV ? 13 : 10,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: widget.isTV ? 2 : 1,
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
