import 'dart:io';
import 'package:android_id/android_id.dart';
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
  static const String _resolvedKey = 'device_id_resolved';
  String? _cachedDeviceId;
  static const AndroidId _androidIdPlugin = AndroidId();

  /// Get a stable device identifier.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    final persistedId = prefs.getString(_resolvedKey);
    final fallbackId = prefs.getString(_fallbackKey);

    // Older app builds may only have persisted the fallback key.
    if (fallbackId != null && fallbackId.isNotEmpty) {
      _cachedDeviceId = fallbackId;
      await prefs.setString(_resolvedKey, _cachedDeviceId!);
      return _cachedDeviceId!;
    }

    // Never switch device identity once we have already resolved one locally.
    // Changing from an old fallback/device-info ID to ANDROID_ID creates a
    // second guest record on the backend for the same physical user.
    if (persistedId != null && persistedId.isNotEmpty) {
      _cachedDeviceId = persistedId;
      return _cachedDeviceId!;
    }

    try {
      if (Platform.isAndroid) {
        final androidId = await _androidIdPlugin.getId();
        if (androidId != null && androidId.isNotEmpty) {
          _cachedDeviceId = androidId;
          await prefs.setString(_resolvedKey, _cachedDeviceId!);
          return _cachedDeviceId!;
        }
      }
    } catch (e) {
      debugPrint('DeviceIdService: Failed to get platform device ID: $e');
    }

    try {
      if (Platform.isAndroid) {
        // Legacy fallback for environments where android_id is unavailable.
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.id.isNotEmpty) {
          _cachedDeviceId = androidInfo.id;
          await prefs.setString(_resolvedKey, _cachedDeviceId!);
          return _cachedDeviceId!;
        }
      }
    } catch (e) {
      debugPrint('DeviceIdService: Failed to get legacy Android device ID: $e');
    }

    // Fallback: use SharedPreferences-stored ID
    var generatedFallbackId = fallbackId;
    if (generatedFallbackId == null) {
      generatedFallbackId =
          DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          Object().hashCode.toRadixString(36);
      await prefs.setString(_fallbackKey, generatedFallbackId);
    }
    _cachedDeviceId = generatedFallbackId;
    await prefs.setString(_resolvedKey, _cachedDeviceId!);
    return _cachedDeviceId!;
  }
}
