import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../state/ar_state.dart';
import '../theme/app_theme.dart';
import 'ar_try_on_screen.dart';

class SearchScreen extends StatefulWidget {
  /// When true, all items are shown immediately below the search bar.
  final bool showAll;
  const SearchScreen({super.key, this.showAll = false});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<JewelryItem> _allItems = [];   // full collection (shown when showAll)
  List<JewelryItem> _results  = [];   // search results
  bool _loading  = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    if (widget.showAll) {
      _loadAll();
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final items = await LocalJewelryService().getAllItems();
    if (mounted) setState(() { _allItems = items; _loading = false; });
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searched = false; _results = []; });
      return;
    }
    setState(() { _loading = true; _searched = true; });
    final r = await LocalJewelryService().searchByName(q);
    if (mounted) setState(() { _results = r; _loading = false; });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.showAll ? 'All Collections' : 'Search',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      onChanged: (v) {
                        setState(() {});
                        if (v.trim().isEmpty && widget.showAll) {
                          setState(() { _searched = false; _results = []; });
                        }
                      },
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search jewelry by name…',
                        hintStyle: GoogleFonts.dmSans(
                            color: AppColors.textHint, fontSize: 14),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textHint, size: 20),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: AppColors.textHint, size: 18),
                                onPressed: () {
                                  _ctrl.clear();
                                  setState(() {
                                    _results = [];
                                    _searched = false;
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _loading ? null : () => _search(_ctrl.text),
                  child: Container(
                    height: 46, width: 46,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.gold));
    }

    // Show search results when user has searched
    if (_searched) {
      if (_results.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  color: AppColors.border, size: 52),
              const SizedBox(height: 14),
              Text('No results found',
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('"${_ctrl.text}" didn\'t match anything',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textHint)),
            ],
          ),
        );
      }
      return _buildGrid(_results);
    }

    // Show all collections when opened via "See all"
    if (widget.showAll) {
      if (_allItems.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                    color: AppColors.goldLight, shape: BoxShape.circle),
                child: const Icon(Icons.diamond_outlined,
                    color: AppColors.gold, size: 32),
              ),
              const SizedBox(height: 16),
              Text('No jewelry yet',
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('Add items in My Shop',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textHint)),
            ],
          ),
        );
      }
      return _buildGrid(_allItems);
    }

    // Default: search prompt
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: AppColors.goldLight, shape: BoxShape.circle),
            child: const Icon(Icons.search, color: AppColors.gold, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Search by model name',
              style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Try "Gold Hoop" or "Diamond Necklace"',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildGrid(List<JewelryItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () => _openAR(item),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 10,
                    offset: Offset(0, 3))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(15)),
                    child: Container(
                      color: AppColors.surfaceAlt,
                      padding: const EdgeInsets.all(12),
                      child: _buildImage(item),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Text(item.name,
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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
                        child: Text(item.type.name.toUpperCase(),
                            style: GoogleFonts.dmSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                                letterSpacing: 0.3)),
                      ),
                      const Spacer(),
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
      },
    );
  }

  Widget _buildImage(JewelryItem item) {
    if (item.isAsset) {
      return Image.asset(item.imagePath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.diamond_outlined,
                  color: AppColors.border, size: 36)));
    }
    final f = File(item.imagePath);
    if (!f.existsSync()) {
      return const Center(
          child: Icon(Icons.diamond_outlined,
              color: AppColors.border, size: 36));
    }
    return Image.file(f,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.diamond_outlined,
                color: AppColors.border, size: 36)));
  }
}

