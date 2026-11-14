import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class GeminiInvoiceOcrService {
  GeminiInvoiceOcrService._();

  static const _storage = FlutterSecureStorage();
  static const _apiKeyStorageName = 'gemini_invoice_ocr_api_key';
  static const _model = 'gemini-2.5-flash-lite';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static Future<String?> readApiKey() =>
      _storage.read(key: _apiKeyStorageName);

  static Future<void> saveApiKey(String value) =>
      _storage.write(key: _apiKeyStorageName, value: value.trim());

  static Future<void> clearApiKey() =>
      _storage.delete(key: _apiKeyStorageName);

  static Future<String> recognizeInvoice(File image, String apiKey) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw const GeminiInvoiceOcrException('Invoice image is empty.');
    }
    if (bytes.length > 15 * 1024 * 1024) {
      throw const GeminiInvoiceOcrException(
        'Image 15 MB se bari hai. Chhoti ya compressed image select karein.',
      );
    }

    final extension = image.path.toLowerCase().split('.').last;
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey.trim(),
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {
                    'text': 'Read this supplier purchase invoice image carefully. '
                        'Transcribe ALL visible printed and handwritten text, preserving '
                        'the original line order and table rows. Pay special attention to '
                        'item names, quantities, units, rates, line amounts, invoice number, '
                        'date, discount, tax and grand total. Do not guess missing or unclear '
                        'characters: write [unclear] for uncertain text. Do not calculate, '
                        'correct, or invent values. Return plain text only, with one invoice '
                        'line per line. This output will be reviewed and edited by a human '
                        'before any stock or supplier account is changed.'
                  },
                  {
                    'inline_data': {
                      'mime_type': mimeType,
                      'data': base64Encode(bytes),
                    }
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': 8192,
            }
          }),
        )
        .timeout(const Duration(seconds: 75));

    if (response.statusCode == 429) {
      throw const GeminiInvoiceOcrException(
        'Gemini ki free-tier request limit filhal poori ho gayi hai. '
        'Koi paid fallback nahi kiya gaya; baad mein dobara try karein.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GeminiInvoiceOcrException(
        'Gemini API key valid nahi ya is model ki access available nahi. '
        'AI Studio se free-tier project ki key check karein.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiInvoiceOcrException(
        'Gemini OCR request fail hui (HTTP ${response.statusCode}). '
        'Internet aur free-tier quota check karein.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const GeminiInvoiceOcrException('Gemini ka response samajh nahi aaya.');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiInvoiceOcrException(
        'Gemini invoice se readable text return nahi kar saka.',
      );
    }
    final content = candidates.first is Map
        ? (candidates.first as Map)['content']
        : null;
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) {
      throw const GeminiInvoiceOcrException('Gemini OCR result empty hai.');
    }
    final text = parts
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .where((part) => part.isNotEmpty)
        .join('\n')
        .trim();
    if (text.isEmpty) {
      throw const GeminiInvoiceOcrException('Gemini invoice se text read nahi kar saka.');
    }
    return text;
  }
}

class GeminiInvoiceOcrException implements Exception {
  final String message;
  const GeminiInvoiceOcrException(this.message);

  @override
  String toString() => message;
}
