enum JewelryType { earring, necklace, chain }

class JewelryItem {
  final String id;
  final String name;
  final String imagePath; // absolute local file path OR asset path (assets/jewelry/...)
  final JewelryType type;
  final double scale;
  final String category;
  final bool isAsset; // true = bundled asset, false = user-added file

  const JewelryItem({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.type,
    this.scale = 1.0,
    this.category = '',
    this.isAsset = false,
  });

  factory JewelryItem.fromMap(Map<String, dynamic> m) => JewelryItem(
        id: m['id'] as String,
        name: m['name'] as String,
        imagePath: m['imagePath'] as String,
        type: JewelryType.values.firstWhere(
          (e) => e.name == m['type'],
          orElse: () => JewelryType.earring,
        ),
        scale: (m['scale'] as num?)?.toDouble() ?? 1.0,
        category: m['category'] as String? ?? '',
        isAsset: (m['isAsset'] as int?) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'type': type.name,
        'scale': scale,
        'category': category,
        'isAsset': isAsset ? 1 : 0,
      };

  JewelryItem copyWith({double? scale}) => JewelryItem(
        id: id,
        name: name,
        imagePath: imagePath,
        type: type,
        scale: scale ?? this.scale,
        category: category,
        isAsset: isAsset,
      );
}
