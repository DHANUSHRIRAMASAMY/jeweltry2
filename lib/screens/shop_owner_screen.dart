import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../theme/app_theme.dart';

// Same materials as SubcategoryScreen so items always match the filter
const _kMaterials = ['Gold', 'Silver', 'Diamond', 'Rose Gold'];

class ShopOwnerScreen extends StatefulWidget {
  const ShopOwnerScreen({super.key});
  @override
  State<ShopOwnerScreen> createState() => _ShopOwnerScreenState();
}

class _ShopOwnerScreenState extends State<ShopOwnerScreen> {
  final _nameCtrl = TextEditingController();
  JewelryType _type = JewelryType.earring;
  String _material = 'Gold';
  double _scale = 1.0;
  File? _pickedFile;
  bool _uploading = false;
  List<JewelryItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await LocalJewelryService().getAllItems();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _pickedFile = File(picked.path));
  }

  Future<void> _save() async {
    if (_pickedFile == null || _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name and pick an image')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      await LocalJewelryService().addJewelry(
        imageFile: _pickedFile!,
        name: _nameCtrl.text.trim(),
        type: _type,
        scale: _scale,
        category: _material,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Jewelry saved')));
        _nameCtrl.clear();
        setState(() {
          _pickedFile = null;
          _scale = 1.0;
          _type = JewelryType.earring;
          _material = 'Gold';
        });
        _loadItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(JewelryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item.name}" from your collection?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) {
      await LocalJewelryService().deleteJewelry(item);
      _loadItems();
    }
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
        title: Text('My Jewelry',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Add New Jewelry'),
            const SizedBox(height: 12),
            _buildForm(),
            const SizedBox(height: 28),
            _sectionTitle('My Collection (${_items.length})'),
            const SizedBox(height: 12),
            _buildList(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary));

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image picker ──────────────────────────────────────────
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 130,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _pickedFile != null
                        ? AppColors.gold
                        : AppColors.border,
                    width: _pickedFile != null ? 1.5 : 1),
              ),
              child: _pickedFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_pickedFile!, fit: BoxFit.contain))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: AppColors.gold, size: 34),
                        const SizedBox(height: 6),
                        Text('Tap to pick image (PNG recommended)',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textHint, fontSize: 12)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Name ──────────────────────────────────────────────────
          _field(_nameCtrl, 'Jewelry Name (e.g. Gold Hoop Earring)'),
          const SizedBox(height: 14),

          // ── Type ──────────────────────────────────────────────────
          Text('Type',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHint,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          Row(
            children: JewelryType.values.map((t) {
              final sel = _type == t;
              final label = t == JewelryType.chain ? 'Chain' : t.name[0].toUpperCase() + t.name.substring(1);
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.gold : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? AppColors.gold : AppColors.border),
                    ),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                            color: sel
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // ── Material ──────────────────────────────────────────────
          Text('Material',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHint,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kMaterials.map((m) {
              final sel = _material == m;
              return GestureDetector(
                onTap: () => setState(() => _material = m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.gold : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppColors.gold : AppColors.border),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: AppColors.gold.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Text(m,
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // ── Scale ─────────────────────────────────────────────────
          Row(
            children: [
              Text('Scale:',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 13)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.gold,
                    thumbColor: AppColors.gold,
                    inactiveTrackColor: AppColors.border,
                    overlayColor: AppColors.gold.withValues(alpha: 0.1),
                  ),
                  child: Slider(
                    value: _scale,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _scale.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(_scale.toStringAsFixed(1),
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Save button ───────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _uploading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Save Jewelry',
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.dmSans(color: AppColors.textHint, fontSize: 13),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.gold, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        ),
      );

  Widget _buildList() {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text('No jewelry yet — add some above',
              style:
                  GoogleFonts.dmSans(color: AppColors.textHint, fontSize: 13)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ItemRow(
        item: _items[i],
        onDelete: () => _confirmDelete(_items[i]),
      ),
    );
  }
}

// ── Item row ──────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final JewelryItem item;
  final VoidCallback onDelete;
  const _ItemRow({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(radius: 12),
      child: Row(
        children: [
          // Thumbnail — fixed size, no JewelryCard nesting
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildThumb(),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Badge(item.type.name, AppColors.gold),
                    const SizedBox(width: 6),
                    if (item.category.isNotEmpty)
                      _Badge(item.category, AppColors.textHint),
                  ],
                ),
              ],
            ),
          ),
          // Delete (only user-added items)
          if (!item.isAsset)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Widget _buildThumb() {
    if (item.isAsset) {
      return Image.asset(item.imagePath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.diamond_outlined, color: AppColors.border));
    }
    final f = File(item.imagePath);
    if (!f.existsSync()) {
      return const Icon(Icons.diamond_outlined, color: AppColors.border);
    }
    return Image.file(f,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.diamond_outlined, color: AppColors.border));
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.dmSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3)),
    );
  }
}
