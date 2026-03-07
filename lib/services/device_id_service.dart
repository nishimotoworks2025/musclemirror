import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to get a stable device identifier.
/// On Android, uses ANDROID_ID which persists across reinstalls.
/// Falls back to a UUID stored in SharedPreferences.
class DeviceIdService {
  static final DeviceIdService _instance = DeviceIdService._internal();
  factory DeviceIdService() => _instance;
  DeviceIdService._internal();

  static const String _fallbackKey = 'device_id_fallback';
  String? _cachedDeviceId;

  /// Get a stable device identifier.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final androidId = androidInfo.id; // ANDROID_ID equivalent
        if (androidId.isNotEmpty) {
          _cachedDeviceId = androidId;
          return _cachedDeviceId!;
        }
      }
    } catch (e) {
      debugPrint('DeviceIdService: Failed to get platform device ID: $e');
    }

    // Fallback: use SharedPreferences-stored ID
    final prefs = await SharedPreferences.getInstance();
    var fallbackId = prefs.getString(_fallbackKey);
    if (fallbackId == null) {
      fallbackId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          Object().hashCode.toRadixString(36);
      await prefs.setString(_fallbackKey, fallbackId);
    }
    _cachedDeviceId = fallbackId;
    return _cachedDeviceId!;
  }
}
