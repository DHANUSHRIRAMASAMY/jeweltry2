import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../theme/app_theme.dart';
import 'generate_result_screen.dart';

class JewelrySelectScreen extends StatefulWidget {
  final String capturedPhotoPath;
  const JewelrySelectScreen({super.key, required this.capturedPhotoPath});

  @override
  State<JewelrySelectScreen> createState() => _JewelrySelectScreenState();
}

class _JewelrySelectScreenState extends State<JewelrySelectScreen> {
  List<JewelryItem> _items = [];
  JewelryItem? _selected;
  bool _loading = true;
  String _activeCategory = 'All';
  static const _categories = ['All', 'Earring', 'Necklace', 'Chain'];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await LocalJewelryService().getAllItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  List<JewelryItem> get _filtered {
    if (_activeCategory == 'All') return _items;
    return _items.where((i) =>
        i.type.name.toLowerCase() == _activeCategory.toLowerCase()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Full-screen captured photo ────────────────────────────────────
          Positioned.fill(
            child: Image.file(
              File(widget.capturedPhotoPath),
              fit: BoxFit.cover,
            ),
          ),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(top: mq.padding.top),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text('Select Jewelry',
                        style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  // Selected item badge
                  if (_selected != null)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_selected!.name,
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),

          // ── Hint when nothing selected ────────────────────────────────────
          if (_selected == null)
            Positioned(
              top: mq.padding.top + 70,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swipe_up_rounded,
                          color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text('Swipe up to browse jewelry',
                          style: GoogleFonts.dmSans(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Draggable jewelry sheet ───────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.18,
            maxChildSize: 0.90,
            snap: true,
            snapSizes: const [0.25, 0.55, 0.90],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 20,
                        offset: Offset(0, -4))
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),

                    // Sheet header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Text('Collections',
                              style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const Spacer(),
                          Text('${_filtered.length} items',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: AppColors.textHint)),
                        ],
                      ),
                    ),

                    // Category chips
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final cat = _categories[i];
                          final active = cat == _activeCategory;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _activeCategory = cat),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.gold
                                    : AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: active
                                        ? AppColors.gold
                                        : AppColors.border),
                              ),
                              child: Text(cat,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: active
                                          ? Colors.white
                                          : AppColors.textSecondary)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Generate button (inside sheet, visible when item selected) ──
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _selected == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _onGenerate,
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                  label: Text('Generate Image',
                                      style: GoogleFonts.dmSans(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.gold,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ),
                    ),

                    // Grid
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.gold))
                          : _filtered.isEmpty
                              ? Center(
                                  child: Text('No items',
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.textHint,
                                          fontSize: 13)))
                              : GridView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 24),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.78,
                                  ),
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) {
                                    final item = _filtered[i];
                                    final isSelected =
                                        _selected?.id == item.id;
                                    return GestureDetector(
                                      onTap: () => setState(() =>
                                          _selected =
                                              isSelected ? null : item),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 180),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.goldLight
                                              : AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.gold
                                                : AppColors.border,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                      color: AppColors.gold
                                                          .withValues(
                                                              alpha: 0.2),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                          0, 2))
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                child: _buildThumb(item),
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      4, 0, 4, 6),
                                              child: Text(item.name,
                                                  style: GoogleFonts.dmSans(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors
                                                          .textPrimary),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign:
                                                      TextAlign.center),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _onGenerate() {
    if (_selected == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GenerateResultScreen(
          capturedPhotoPath: widget.capturedPhotoPath,
          selectedItem: _selected!,
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ).then((action) {
      if (action == 'retake') {
        // Pop back to camera
        Navigator.pop(context);
      }
      // 'change' → stay on this screen, user picks another jewel
    });
  }

  Widget _buildThumb(JewelryItem item) {
    if (item.isAsset) {
      return Image.asset(item.imagePath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.diamond_outlined,
              color: AppColors.border, size: 24));
    }
    final f = File(item.imagePath);
    if (!f.existsSync()) {
      return const Icon(Icons.diamond_outlined,
          color: AppColors.border, size: 24);
    }
    return Image.file(f,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.diamond_outlined,
            color: AppColors.border, size: 24));
  }
}
