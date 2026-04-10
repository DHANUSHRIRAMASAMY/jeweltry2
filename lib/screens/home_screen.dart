import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../state/ar_state.dart';
import '../theme/app_theme.dart';
import '../widgets/jewelry_card.dart';
import 'ar_try_on_screen.dart';
import 'search_screen.dart';
import 'shop_owner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<JewelryItem> _allItems = [];
  bool _loading = true;
  String _activeCategory = 'All';
  static const _categories = ['All', 'Earring', 'Necklace', 'Chain', 'Pendant'];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = await LocalJewelryService().getAllItems();
    if (mounted) setState(() { _allItems = items; _loading = false; });
  }

  List<JewelryItem> get _filtered {
    if (_activeCategory == 'All') return _allItems;
    return _allItems
        .where((i) => i.type.name.toLowerCase() == _activeCategory.toLowerCase())
        .toList();
  }

  void _openAR(JewelryItem item) {
    ArState.instance.select(item);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ArTryOnScreen(initialItem: item),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

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
            _TopBar(
              onSearchTap: () =>
                  Navigator.push(context, _fade(const SearchScreen())),
              onShopTap: () async {
                await Navigator.push(context, _fade(const ShopOwnerScreen()));
                _loadItems();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.gold,
                onRefresh: _loadItems,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _HeroCameraCard(
                        onTap: () => Navigator.push(
                            context, _fade(const ArTryOnScreen())),
                      ),
                      const SizedBox(height: 28),
                      // Section header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Collections',
                                style: GoogleFonts.dmSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                  context, _fade(const SearchScreen())),
                              child: Text('See all',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _CategoryChips(
                        active: _activeCategory,
                        categories: _categories,
                        onSelect: (c) => setState(() => _activeCategory = c),
                      ),
                      const SizedBox(height: 16),
                      // Horizontal jewelry list
                      SizedBox(
                        height: 148,
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.gold))
                            : _filtered.isEmpty
                                ? Center(
                                    child: Text('No items yet',
                                        style: GoogleFonts.dmSans(
                                            color: AppColors.textHint,
                                            fontSize: 13)))
                                : ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    itemCount: _filtered.length,
                                    itemBuilder: (_, i) => JewelryCard(
                                      item: _filtered[i],
                                      onTap: () => _openAR(_filtered[i]),
                                    ),
                                  ),
                      ),
                      const SizedBox(height: 28),
                      // Quick actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('Quick Actions',
                            style: GoogleFonts.dmSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.camera_alt_outlined,
                                label: 'Try On',
                                onTap: () => Navigator.push(
                                    context, _fade(const ArTryOnScreen())),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.search_rounded,
                                label: 'Search',
                                onTap: () => Navigator.push(
                                    context, _fade(const SearchScreen())),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.store_outlined,
                                label: 'My Shop',
                                onTap: () async {
                                  await Navigator.push(context,
                                      _fade(const ShopOwnerScreen()));
                                  _loadItems();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
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
                width: 36,
                height: 36,
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
                  Text('Search jewelry by name…',
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

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCameraCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroCameraCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.width * 0.52).clamp(160.0, 220.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: h,
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
                  color: Color(0x18C9A84C),
                  blurRadius: 20,
                  offset: Offset(0, 8))
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withOpacity(0.08)),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.gold.withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: const Icon(Icons.camera_alt_outlined,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(height: 12),
                      Text('Try On Jewelry',
                          style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.2)),
                      const SizedBox(height: 3),
                      Text('See how it looks on you in real time',
                          style: GoogleFonts.dmSans(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 14),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category chips ────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final String active;
  final List<String> categories;
  final ValueChanged<String> onSelect;
  const _CategoryChips(
      {required this.active,
      required this.categories,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isActive = cat == active;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.gold : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isActive ? AppColors.gold : AppColors.border),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                            color: AppColors.gold.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]
                    : null,
              ),
              child: Text(cat,
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.white
                          : AppColors.textSecondary)),
            ),
          );
        },
      ),
    );
  }
}

// ── Quick action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: cardDecoration(radius: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.gold, size: 22),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
