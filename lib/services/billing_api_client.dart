import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/me_status.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

/// API client for billing-related server endpoints (ported from TrueSkin).
/// Handles purchase registration and user status retrieval.
class BillingApiClient {
  static final BillingApiClient _instance = BillingApiClient._internal();
  factory BillingApiClient() => _instance;
  BillingApiClient._internal();

  final http.Client _client = http.Client();
  final String _baseUrl = AppConfig.apiBaseUrl;
  final AuthService _authService = AuthService();

  /// Register a Google Play purchase with the server.
  /// The server verifies the purchase with Google Play API and stores it in DynamoDB.
  Future<Map<String, dynamic>> registerPurchase(
      String productId, String purchaseToken) async {
    final idToken = _authService.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Authorization required');
    }

    final uri = Uri.parse('$_baseUrl/billing/register_google');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    final body = jsonEncode({
      'product_id': productId,
      'google_purchase_token': purchaseToken,
    });

    debugPrint('[BillingApiClient] Registering purchase: $productId');

    final response = await _client.post(uri, headers: headers, body: body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is String) {
        try {
          final doubleDecoded = jsonDecode(decoded);
          if (doubleDecoded is Map<String, dynamic>) {
            return doubleDecoded;
          }
        } catch (_) {}
        return {'message': decoded};
      } else {
        return {'response': decoded};
      }
    } else {
      String errorMsg = 'Failed to register: ${response.statusCode}';
      try {
        final bodyObj = jsonDecode(utf8.decode(response.bodyBytes));
        if (bodyObj is Map && bodyObj.containsKey('message')) {
          errorMsg += ' ${bodyObj['message']}';
        } else {
          errorMsg += ' ${response.body}';
        }
      } catch (e) {
        errorMsg += ' ${response.body}';
      }
      throw Exception(errorMsg);
    }
  }

  /// Fetch the current user's status from the server.
  /// Returns plan, remaining usage count, feature flags, etc.
  Future<MeStatus> fetchMe() async {
    final idToken = _authService.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Authorization required');
    }

    final uri = Uri.parse('$_baseUrl/me');
    final headers = {
      'Authorization': 'Bearer $idToken',
    };

    debugPrint('[BillingApiClient] Fetching /me status');

    final response = await _client.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final rawBody = utf8.decode(response.bodyBytes);
      debugPrint('[BillingApiClient] /me response: $rawBody');

      final dynamic decoded = jsonDecode(rawBody);

      Map<String, dynamic> json;

      if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else if (decoded is String) {
        try {
          final doubleDecoded = jsonDecode(decoded);
          if (doubleDecoded is Map<String, dynamic>) {
            json = doubleDecoded;
          } else {
            throw Exception('Unexpected response format: $decoded');
          }
        } catch (_) {
          throw Exception('Unexpected response format: $decoded');
        }
      } else {
        throw Exception('Unexpected response type: ${decoded.runtimeType}');
      }

      // Handle potential nested body from API Gateway
      if (json.containsKey('body') && json['body'] is String) {
        final bodyJson = jsonDecode(json['body'] as String);
        if (bodyJson is Map<String, dynamic>) {
          debugPrint('[BillingApiClient] Parsed from nested body: $bodyJson');
          return MeStatus.fromJson(bodyJson);
        }
      }

      return MeStatus.fromJson(json);
    } else {
      throw Exception(
          'Failed to fetch me status: ${response.statusCode} ${response.body}');
    }
  }

  /// Fetch guest usage count from the server.
  Future<int> fetchGuestUsage(String deviceId) async {
    final uri = Uri.parse('$_baseUrl/guest/usage');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'device_id': deviceId,
      'action': 'get',
    });

    debugPrint('[BillingApiClient] Fetching guest usage for device: $deviceId');

    final response = await _client.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded.containsKey('guestTotalUsedCount')) {
        return decoded['guestTotalUsedCount'] as int;
      }
      return 0;
    } else {
      debugPrint('[BillingApiClient] Failed to fetch guest usage: ${response.statusCode}');
      return 0; // fallback to 0 if API fails, or throw? better to fail gracefully.
    }
  }

  /// Increment guest usage count on the server.
  Future<void> incrementGuestUsage(String deviceId) async {
    final uri = Uri.parse('$_baseUrl/guest/usage');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'device_id': deviceId,
      'action': 'increment',
    });

    debugPrint('[BillingApiClient] Incrementing guest usage for device: $deviceId');

    final response = await _client.post(uri, headers: headers, body: body);

    if (response.statusCode != 200) {
      debugPrint('[BillingApiClient] Failed to increment guest usage: ${response.statusCode}');
    }
  }

  /// Delete account on the server.
  Future<void> deleteAccount() async {
    final idToken = _authService.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('ログインが必要です');
    }

    final uri = Uri.parse('$_baseUrl/account/delete');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };

    debugPrint('[BillingApiClient] Deleting account');

    final response = await _client.post(uri, headers: headers);

    if (response.statusCode != 200 && response.statusCode != 204) {
      String errorMsg = 'アカウント削除に失敗しました';
      try {
        final bodyObj = jsonDecode(utf8.decode(response.bodyBytes));
        if (bodyObj is Map && bodyObj.containsKey('message')) {
          errorMsg = bodyObj['message'] as String;
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }
}
