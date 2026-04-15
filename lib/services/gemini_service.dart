import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/jewelry_item.dart';

/// Calls the Gemini 2.0 Flash Preview image generation API to produce a
/// photorealistic image of the user naturally wearing the selected jewelry.
class GeminiService {
  static const String _apiKey = 'AIzaSyDajo9U-HlFCWExpVOIf1-J7SMhTV1r0mo';

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash-image:generateContent';

  /// Sends the user photo + jewelry image to Gemini and returns the
  /// path to the generated result image saved in the temp directory.
  static Future<String> generateJewelryImage({
    required String userPhotoPath,
    required JewelryItem jewelryItem,
  }) async {
    // Read both images as base64
    final userBytes    = await File(userPhotoPath).readAsBytes();
    final jewelryBytes = await File(jewelryItem.imagePath).readAsBytes();

    final userB64    = base64Encode(userBytes);
    final jewelryB64 = base64Encode(jewelryBytes);

    // Detect mime type
    final userMime    = _mimeType(userPhotoPath);
    final jewelryMime = _mimeType(jewelryItem.imagePath);

    // Build the prompt
    final prompt = _buildPrompt(jewelryItem);

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': userMime,
                'data': userB64,
              }
            },
            {
              'inline_data': {
                'mime_type': jewelryMime,
                'data': jewelryB64,
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE', 'TEXT'],
      },
    });

    debugPrint('Gemini: sending request…');

    final response = await http.post(
      Uri.parse('$_endpoint?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 60));

    debugPrint('Gemini: status ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // Extract the image part from the response
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates');
    }

    final parts = candidates[0]['content']['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini returned no parts');
    }

    // Find the image part
    Map<String, dynamic>? imagePart;
    for (final part in parts) {
      if (part['inline_data'] != null) {
        imagePart = part as Map<String, dynamic>;
        break;
      }
    }

    if (imagePart == null) {
      throw Exception(
          'Gemini did not return an image. Response: ${response.body}');
    }

    final imageData = imagePart['inline_data']['data'] as String;
    final imageBytes = base64Decode(imageData);

    // Save to temp directory
    final dir = await getTemporaryDirectory();
    final outPath = p.join(
        dir.path, 'generated_${DateTime.now().millisecondsSinceEpoch}.png');
    await File(outPath).writeAsBytes(imageBytes);

    debugPrint('Gemini: result saved to $outPath');
    return outPath;
  }

  static String _buildPrompt(JewelryItem item) {
    final type = item.type.name;
    switch (item.type) {
      case JewelryType.earring:
        return 'The first image is a photo of a person. '
            'The second image shows ${item.name} earrings. '
            'Generate a new photorealistic image of the same person '
            'naturally wearing these exact earrings on both ears. '
            'The earrings should look like they are physically on the person — '
            'with correct lighting, shadows, and skin interaction. '
            'Do NOT paste the earring image on top. '
            'Regenerate the ear area so the earrings look naturally worn. '
            'Keep the person\'s face, hair, and everything else identical.';
      case JewelryType.necklace:
      case JewelryType.chain:
        return 'The first image is a photo of a person. '
            'The second image shows a ${item.name} ($type). '
            'Generate a new photorealistic image of the same person '
            'naturally wearing this $type around their neck. '
            'The $type should look physically worn — '
            'with correct draping, lighting, and shadows on the skin. '
            'Do NOT paste the image on top. '
            'Keep the person\'s face and body identical, only add the $type.';
    }
  }

  static String _mimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png'            => 'image/png',
      '.webp'           => 'image/webp',
      _                 => 'image/jpeg',
    };
  }
}
