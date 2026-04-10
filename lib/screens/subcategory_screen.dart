import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../state/ar_state.dart';
import '../theme/app_theme.dart';
import 'ar_try_on_screen.dart';

class SubcategoryScreen extends StatefulWidget {
  final JewelryType type;
  final String typeLabel; // "Earrings", "Necklace", "Chain & Pendant"

  const SubcategoryScreen({
    super.key,
    required this.type,
    required this.typeLabel,
  });

  @override
  State<SubcategoryScreen> createState() => _SubcategoryScreenState();
}

class _SubcategoryScreenState extends State<SubcategoryScreen> {
  static const _materials = ['Gold', 'Silver', 'Diamond', 'Rose Gold'];

  String _selectedMaterial = 'Gold';
  List<JewelryItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = await LocalJewelryService()
        .getItemsByTypeAndCategory(widget.type, _selectedMaterial);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  void _selectMaterial(String m) {
    if (_selectedMaterial == m) return;
    setState(() => _selectedMaterial = m);
    _loadItems();
  }

  void _openAR(JewelryItem item) {
    ArState.instance.select(item);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ArTryOnScreen(initialItem: item),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.typeLabel,
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppColors.textPrimary)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Material filter chips ────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Material',
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHint,
                        letterSpacing: 0.5)),
                const SizedBox(height: 10),
                Row(
                  children: _materials.map((m) {
                    final active = m == _selectedMaterial;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _selectMaterial(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: active ? AppColors.gold : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: active ? AppColors.gold : AppColors.border),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                        color: AppColors.gold.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3))
                                  ]
                                : null,
                          ),
                          child: Text(m,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? Colors.white
                                      : AppColors.textSecondary)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),

          // ── Result count ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              _loading
                  ? 'Loading...'
                  : '${_items.length} item${_items.length == 1 ? '' : 's'} · $_selectedMaterial ${widget.typeLabel}',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ),

          // ── Items grid ───────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? _EmptyState(
                        material: _selectedMaterial,
                        type: widget.typeLabel)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) =>
                            _ItemCard(item: _items[i], onTap: () => _openAR(_items[i])),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final JewelryItem item;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: Container(
                  color: AppColors.surfaceAlt,
                  padding: const EdgeInsets.all(12),
                  child: _buildImage(),
                ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                item.name,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category,
                      style: GoogleFonts.dmSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          letterSpacing: 0.3),
                    ),
                  ),
                  const Spacer(),
                  // Try-on button
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.camera_alt_outlined,
                        color: Colors.white, size: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (item.isAsset) {
      return Image.asset(item.imagePath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _Placeholder());
    }
    final f = File(item.imagePath);
    if (!f.existsSync()) return const _Placeholder();
    return Image.file(f,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _Placeholder());
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(Icons.diamond_outlined, color: AppColors.border, size: 36),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String material;
  final String type;
  const _EmptyState({required this.material, required this.type});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: AppColors.goldLight, shape: BoxShape.circle),
              child: const Icon(Icons.diamond_outlined,
                  color: AppColors.gold, size: 36),
            ),
            const SizedBox(height: 16),
            Text('No $material $type yet',
                style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Add items in My Shop to see them here',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textHint),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
