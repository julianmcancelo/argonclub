import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tv_focusable_item.dart';

class SidebarNav extends StatefulWidget {
  final ValueChanged<int> onMenuSelected;
  final int selectedIndex;

  const SidebarNav({
    Key? key,
    required this.onMenuSelected,
    this.selectedIndex = 0,
  }) : super(key: key);

  @override
  State<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<SidebarNav> {
  bool _isExpanded = false;

  final List<Map<String, dynamic>> _menuItems = [
    {'icon': Icons.home, 'label': 'Inicio', 'id': 0},
    {'icon': Icons.movie, 'label': 'Películas', 'id': 1},
    {'icon': Icons.tv, 'label': 'Series', 'id': 2},
    {'icon': Icons.live_tv, 'label': 'En Vivo', 'id': 3},
    {'icon': Icons.search, 'label': 'Buscar', 'id': 4},
    {'icon': Icons.bug_report, 'label': 'Errores', 'id': 5},
  ];

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _isExpanded = hasFocus;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: _isExpanded ? 240 : 80,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          border: Border(
            right: BorderSide(
              color: Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Logo area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const Icon(Icons.play_circle_filled, color: Colors.white, size: 40),
                secondChild: Row(
                  children: [
                    const Icon(Icons.play_circle_filled, color: Colors.white, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Argon',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Menu Items
            Expanded(
              child: ListView.builder(
                itemCount: _menuItems.length,
                itemBuilder: (context, index) {
                  final item = _menuItems[index];
                  final isSelected = widget.selectedIndex == item['id'];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    child: TvFocusableItem(
                      onPressed: () {
                        widget.onMenuSelected(item['id']);
                      },
                      focusColor: Colors.white,
                      scaleOnFocus: 1.05,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item['icon'],
                              color: isSelected ? Colors.white : Colors.white70,
                              size: 24,
                            ),
                            if (_isExpanded) ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  item['label'],
                                  style: GoogleFonts.outfit(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontSize: 18,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ],
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
    );
  }
}
