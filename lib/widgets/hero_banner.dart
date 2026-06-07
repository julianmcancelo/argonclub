import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tv_focusable_item.dart';
import '../screens/details_screen.dart';

class HeroBanner extends StatelessWidget {
  final dynamic item;
  final bool isTV;
  final String type;

  const HeroBanner({
    Key? key,
    required this.item,
    required this.isTV,
    required this.type,
  }) : super(key: key);

  String _resolveId(dynamic item) {
    return item['movies_id']?.toString() ??
        item['videos_id']?.toString() ??
        item['live_tv_id']?.toString() ??
        '';
  }

  void _openDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          itemData: item,
          type: type,
          id: _resolveId(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox.shrink();

    // Use original size for high-res banner
    String imageUrl = item['thumbnail_url'] ?? item['poster_url'] ?? '';
    if (imageUrl.contains('w500')) {
      imageUrl = imageUrl.replaceAll('w500', 'original');
    }

    final title = item['title'] ?? item['tv_name'] ?? '';
    final description = item['description'] ?? '';

    return Container(
      height: isTV ? MediaQuery.of(context).size.height * 0.70 : 400,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
            placeholder: (context, url) => Container(color: const Color(0xFF0F0F0F)),
            errorWidget: (context, url, error) => Container(color: const Color(0xFF0F0F0F)),
          ),
          
          // Gradients for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF0F0F0F),
                  const Color(0xFF0F0F0F).withOpacity(0.8),
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.8, 1.0],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF0F0F0F).withOpacity(0.9),
                  const Color(0xFF0F0F0F).withOpacity(0.5),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Content
          Positioned(
            left: isTV ? 48 : 24,
            bottom: isTV ? 48 : 24,
            right: isTV ? MediaQuery.of(context).size.width * 0.4 : 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: isTV ? 56 : 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                if (description.isNotEmpty) ...[
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: isTV ? 18 : 14,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 32),
                ],
                Row(
                  children: [
                    TvFocusableItem(
                      onPressed: () => _openDetails(context),
                      focusColor: Colors.white,
                      scaleOnFocus: 1.1,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTV ? 32 : 24,
                          vertical: isTV ? 16 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow, color: Colors.black, size: isTV ? 28 : 24),
                            const SizedBox(width: 8),
                            Text(
                              'Reproducir',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontSize: isTV ? 20 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TvFocusableItem(
                      onPressed: () => _openDetails(context),
                      focusColor: Colors.white,
                      scaleOnFocus: 1.1,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTV ? 32 : 24,
                          vertical: isTV ? 16 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.white, size: isTV ? 28 : 24),
                            const SizedBox(width: 8),
                            Text(
                              'Más Info',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: isTV ? 20 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
