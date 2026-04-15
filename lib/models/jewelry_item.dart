enum JewelryType { earring, necklace, chain }

class JewelryItem {
  final String id;
  final String name;
  final String imagePath;       // full image (or left earring if isPair)
  final JewelryType type;
  final double scale;
  final String category;
  final bool isAsset;
  final String? glbPath;        // optional .glb for 3D viewer
  final String? rightImagePath; // right earring crop (null = single earring)

  const JewelryItem({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.type,
    this.scale = 1.0,
    this.category = '',
    this.isAsset = false,
    this.glbPath,
    this.rightImagePath,
  });

  /// True when the uploaded image was a pair and has been split.
  bool get isPair => rightImagePath != null && rightImagePath!.isNotEmpty;

  bool get has3dModel => glbPath != null && glbPath!.isNotEmpty;

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
        glbPath: m['glbPath'] as String?,
        rightImagePath: m['rightImagePath'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'type': type.name,
        'scale': scale,
        'category': category,
        'isAsset': isAsset ? 1 : 0,
        'glbPath': glbPath,
        'rightImagePath': rightImagePath,
      };

  JewelryItem copyWith({double? scale, String? glbPath}) => JewelryItem(
        id: id,
        name: name,
        imagePath: imagePath,
        type: type,
        scale: scale ?? this.scale,
        category: category,
        isAsset: isAsset,
        glbPath: glbPath ?? this.glbPath,
        rightImagePath: rightImagePath,
      );
}
