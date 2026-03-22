import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/muscle_data.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

/// Stage 1: Clothing/Composition check
/// Stage 2: Muscle evaluation

/// Exception thrown when the API indicates the Pro subscription has expired or is unauthorized.
class ProExpiredException implements Exception {
  final String message;
  ProExpiredException(this.message);
  @override
  String toString() => 'ProExpiredException: $message';
}

class GeminiService {
  final String _apiBaseUrl;

  GeminiService() : _apiBaseUrl = AppConfig.apiBaseUrl;

  /// Stage 1: Check if the image is suitable for muscle evaluation.
  Future<PreCheckResult> preCheck(Uint8List imageBytes) async {
    try {
      final imageBase64 = base64Encode(imageBytes);
      
      final idToken = await AuthService().getValidIdToken();
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/diagnosis'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
          if (idToken != null) 'x-mm-id-token': idToken,
        },
        body: jsonEncode({
          'action': 'pre-check',
          'image_base64': imageBase64,
        }),
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception(
          'API Gateway error: ${response.statusCode} body=$errorBody',
        );
      }

      final rawBody = utf8.decode(response.bodyBytes);
      final decoded = jsonDecode(rawBody);
      final json = decoded is Map<String, dynamic>
          ? decoded
          : decoded is String
              ? jsonDecode(decoded) as Map<String, dynamic>
              : <String, dynamic>{};
      // The Lambda might wrap the object in another body string if not handled by proxy integration correctly
      // But we used proxy integration, so response.body should be the Lambda's response body.
      
      // If Lambda returns {statusCode: 200, body: "JSON_STRING"}, proxy integration should handle it.
      // In our code, Lambda returned {statusCode: 200, body: json_str}.
      
      return PreCheckResult.fromJson(json);
    } catch (e, stack) {
      debugPrint('Gemini preCheck error: $e');
      debugPrint('$stack');
      return const PreCheckResult(
        level: PreCheckLevel.warn,
        reasonCode: 'api_error',
      );
    }
  }

  /// Stage 2: Full muscle evaluation.
  Future<MuscleEvaluation> evaluate({
    required Uint8List imageBytes,
    required EvaluationType evaluationType,
    bool isPro = false,
  }) async {
    try {
      final imageBase64 = base64Encode(imageBytes);

      final idToken = await AuthService().getValidIdToken();
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/diagnosis'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
          if (idToken != null) 'x-mm-id-token': idToken,
        },
        body: jsonEncode({
          'action': 'evaluate',
          'image_base64': imageBase64,
          'params': {
            'evaluation_type': evaluationType.name,
            'is_pro': isPro,
          }
        }),
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw ProExpiredException('API Gateway error: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        throw Exception('API Gateway error: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      return MuscleEvaluation.fromJson({
        ...json,
        'evaluated_at': DateTime.now().toIso8601String(),
        'evaluation_type': evaluationType.name,
      });
    } catch (e, stack) {
      if (e is ProExpiredException) {
        rethrow;
      }
      debugPrint('Gemini evaluate error: $e');
      debugPrint('$stack');
      return MuscleEvaluation.sample();
    }
  }
}

/// Reason code descriptions for pre-check failures.
const preCheckReasonMessages = {
  'low_light': '照明が不十分です。明るい場所で撮影してください。',
  'heavy_clothing': '厚手の服を着ています。薄手の服で撮影してください。',
  'long_sleeves': '長袖を着ています。半袖または袖なしで撮影してください。',
  'busy_pattern': '柄が多い服を着ています。無地の服を推奨します。',
  'loose_fit': 'ゆったりした服を着ています。フィットした服で撮影してください。',
  'poor_framing': '上半身が十分に写っていません。構図を調整してください。',
  'bad_pose': 'ポーズが適切ではありません。正面を向いて立ってください。',
  'inappropriate_exposure': '不適切な露出が検知されました。公序良俗に反する服装や下着での撮影は控えてください。',
  'api_error': '画像の処理中にエラーが発生しました。再試行してください。',
  'unknown': '画像を確認できませんでした。再撮影してください。',
};
