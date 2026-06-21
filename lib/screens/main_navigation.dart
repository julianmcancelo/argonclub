import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/argon_theme.dart';

import 'home_dashboard_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../services/remote_control_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late final List<FocusNode> _navFocusNodes;
  final FocusNode _contentBridgeFocusNode = FocusNode(debugLabel: 'tv-content-bridge');

  @override
  void initState() {
    super.initState();
    _navFocusNodes = List.generate(
      6,
      (index) => FocusNode(debugLabel: 'tv-nav-$index'),
    );
  }

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    _contentBridgeFocusNode.dispose();
    super.dispose();
  }

  bool _isTV(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 960 && size.width > size.height;
  }

  List<Widget> _buildPages() {
    return [
      HomeDashboardScreen(
        key: const ValueKey('home'),
        onOpenSection: (index) {
          _openSection(index, moveFocusToContent: true);
        },
      ),
      const HomeScreen(key: ValueKey('movies'), apiEndpoint: 'movies', title: 'Peliculas'),
      const HomeScreen(key: ValueKey('tvseries'), apiEndpoint: 'tvseries', title: 'Series'),
      const HomeScreen(key: ValueKey('live'), apiEndpoint: 'live', title: 'TV en Vivo'),
      const SearchScreen(key: ValueKey('search')),
      const SettingsScreen(key: ValueKey('settings')),
    ];
  }

  void _openSection(int index, {bool moveFocusToContent = false}) {
    if (!mounted) return;
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
    if (moveFocusToContent) {
      _moveFocusToContent();
    }
  }

  void _moveFocusToContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = FocusManager.instance.primaryFocus;
      final moved = current?.focusInDirection(TraversalDirection.right) ?? false;
      if (!moved) {
        _contentBridgeFocusNode.requestFocus();
        _contentBridgeFocusNode.focusInDirection(TraversalDirection.right);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _isTV(context);
    final pages = _buildPages();

    if (isTV) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: FocusTraversalGroup(
          child: Row(
            children: [
              Container(
                width: 116,
                decoration: BoxDecoration(
                  color: Colors.grey[950],
                  border: Border(
                    right: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TVNavItem(
                      icon: Icons.home,
                      label: 'Inicio',
                      focusNode: _navFocusNodes[0],
                      isSelected: _currentIndex == 0,
                      onTap: () => _openSection(0),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const SizedBox(height: 8),
                    _TVNavItem(
                      icon: Icons.movie,
                      label: 'Peliculas',
                      focusNode: _navFocusNodes[1],
                      isSelected: _currentIndex == 1,
                      onTap: () => _openSection(1),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const SizedBox(height: 8),
                    _TVNavItem(
                      icon: Icons.tv,
                      label: 'Series',
                      focusNode: _navFocusNodes[2],
                      isSelected: _currentIndex == 2,
                      onTap: () => _openSection(2),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const SizedBox(height: 8),
                    _TVNavItem(
                      icon: Icons.live_tv,
                      label: 'En Vivo',
                      focusNode: _navFocusNodes[3],
                      isSelected: _currentIndex == 3,
                      onTap: () => _openSection(3),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const SizedBox(height: 8),
                    _TVNavItem(
                      icon: Icons.search,
                      label: 'Buscar',
                      focusNode: _navFocusNodes[4],
                      isSelected: _currentIndex == 4,
                      onTap: () => _openSection(4),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const SizedBox(height: 8),
                     _TVNavItem(
                      icon: Icons.settings,
                      label: 'Ajustes',
                      focusNode: _navFocusNodes[5],
                      isSelected: _currentIndex == 5,
                      onTap: () => _openSection(5),
                      onMoveRight: _moveFocusToContent,
                    ),
                    const _TVRemoteStatusIndicator(),
                  ],
                ),
              ),
              Expanded(
                child: Focus(
                  focusNode: _contentBridgeFocusNode,
                  child: KeyedSubtree(
                    key: ValueKey('tv-content-$_currentIndex'),
                    child: pages[_currentIndex],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: ArgonTheme.sky,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: 'Peliculas'),
          BottomNavigationBarItem(icon: Icon(Icons.tv), label: 'Series'),
          BottomNavigationBarItem(icon: Icon(Icons.live_tv), label: 'En Vivo'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Buscar'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}

class _TVNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final FocusNode focusNode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onMoveRight;

  const _TVNavItem({
    required this.icon,
    required this.label,
    required this.focusNode,
    required this.isSelected,
    required this.onTap,
    required this.onMoveRight,
  });

  @override
  State<_TVNavItem> createState() => _TVNavItemState();
}

class _TVNavItemState extends State<_TVNavItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isSelected || _isFocused;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.isSelected,
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onMoveRight();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          widget.onMoveRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isHighlighted ? ArgonTheme.sky.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: _isFocused
                ? Border.all(color: ArgonTheme.sky, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: isHighlighted ? ArgonTheme.sky : Colors.white54, size: 32),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: isHighlighted ? ArgonTheme.sky : Colors.white54,
                  fontSize: 11,
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TVRemoteStatusIndicator extends StatefulWidget {
  const _TVRemoteStatusIndicator({Key? key}) : super(key: key);

  @override
  State<_TVRemoteStatusIndicator> createState() => _TVRemoteStatusIndicatorState();
}

class _TVRemoteStatusIndicatorState extends State<_TVRemoteStatusIndicator> {
  final RemoteControlService _service = RemoteControlService();
  bool _paired = false;
  String? _code;
  StreamSubscription? _codeSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _service.connect();
      _service.registerTv();
      _codeSub = _service.pairingCodeStream.listen((code) {
        if (mounted) setState(() => _code = code);
      });
      _statusSub = _service.pairingStatusStream.listen((paired) {
        if (mounted) setState(() => _paired = paired);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_paired) {
      return Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 10),
            SizedBox(width: 4),
            Text(
              'RC OK',
              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (_code != null) {
      return Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: ArgonTheme.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ArgonTheme.gold.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_remote_rounded, color: ArgonTheme.gold, size: 16),
            const SizedBox(height: 4),
            Text(
              'RC: $_code',
              style: const TextStyle(
                color: ArgonTheme.gold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
