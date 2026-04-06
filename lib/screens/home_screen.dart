import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';
import 'shop_owner_screen.dart';
import 'subcategory_screen.dart';
import 'ar_try_on_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _collections = [
    _Collection(
      type: JewelryType.earring,
      label: 'Earrings',
      subtitle: 'Studs, hoops, drops & more',
      icon: Icons.earbuds_outlined,
      gradient: [Color(0xFFFFF8EC), Color(0xFFFDF3DC)],
      borderColor: Color(0xFFEDD9A3),
    ),
    _Collection(
      type: JewelryType.necklace,
      label: 'Necklace',
      subtitle: 'Pendants, chokers & layered',
      icon: Icons.favorite_border_rounded,
      gradient: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
      borderColor: Color(0xFFBDCAF5),
    ),
    _Collection(
      type: JewelryType.chain,
      label: 'Chain & Pendant',
      subtitle: 'Gold, silver & diamond chains',
      icon: Icons.link_rounded,
      gradient: [Color(0xFFF2FFF4), Color(0xFFE6F9E8)],
      borderColor: Color(0xFFB2DDB6),
    ),
  ];

  PageRoute _fade(Widget p) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => p,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 220),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _TopBar(
              onSearchTap: () =>
                  Navigator.push(context, _fade(const SearchScreen())),
              onShopTap: () =>
                  Navigator.push(context, _fade(const ShopOwnerScreen())),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      // Hero banner
                      _HeroBanner(
                        onTap: () => Navigator.push(
                            context, _fade(const ArTryOnScreen())),
                      ),
                      const SizedBox(height: 28),
                      // Section title
                      Text('Collections',
                          style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Choose a category to explore',
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: AppColors.textHint)),
                      const SizedBox(height: 16),
                      // 3 collection cards
                      ..._collections.map((c) => _CollectionCard(
                            collection: c,
                            onTap: () => Navigator.push(
                              context,
                              _fade(SubcategoryScreen(
                                  type: c.type, typeLabel: c.label)),
                            ),
                          )),
                      const SizedBox(height: 28),
                      // Footer
                      Center(
                        child: Text('JewelTry · Works Offline',
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: AppColors.textHint,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 24),
                    ],
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

// ── Data class ────────────────────────────────────────────────────────────────

class _Collection {
  final JewelryType type;
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Color borderColor;
  const _Collection({
    required this.type,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.borderColor,
  });
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onShopTap;
  const _TopBar({required this.onSearchTap, required this.onShopTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.diamond_outlined,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('JewelTry',
                        style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.3)),
                    Text('Try before you buy',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onShopTap,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border)),
                  child: const Icon(Icons.store_outlined,
                      color: AppColors.textSecondary, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onSearchTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: AppColors.textHint, size: 20),
                  const SizedBox(width: 8),
                  Text('Search jewelry by name...',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textHint, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero banner ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF5EDD6), Color(0xFFFDF8EE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8D9B0)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18C9A84C), blurRadius: 20, offset: Offset(0, 8))
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -16, top: -16,
              child: Container(
                width: 110, height: 110,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0x14C9A84C)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x50C9A84C),
                                  blurRadius: 8,
                                  offset: Offset(0, 3))
                            ],
                          ),
                          child: const Icon(Icons.camera_alt_outlined,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(height: 10),
                        Text('Try On Now',
                            style: GoogleFonts.dmSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.2)),
                        const SizedBox(height: 3),
                        Text('See jewelry on your face live',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Open Camera',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.face_retouching_natural_outlined,
                      size: 64, color: Color(0x40C9A84C)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Collection card ───────────────────────────────────────────────────────────

class _CollectionCard extends StatelessWidget {
  final _Collection collection;
  final VoidCallback onTap;
  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: collection.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: collection.borderColor),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: collection.borderColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Icon(collection.icon, color: AppColors.gold, size: 26),
            ),
            const SizedBox(width: 16),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(collection.label,
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(collection.subtitle,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  // Material preview chips
                  Wrap(
                    spacing: 6,
                    children: ['Gold', 'Silver', 'Diamond', 'Rose Gold']
                        .map((m) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: collection.borderColor),
                              ),
                              child: Text(m,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary)),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
