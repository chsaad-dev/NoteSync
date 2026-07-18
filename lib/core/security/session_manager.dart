import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:isar/isar.dart';

import '../di/injection_container.dart';
import 'encryption_service.dart';

class SessionManager {
  static const String _deviceIdKey = 'device_id';
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSubscription;

  // Get or generate a persistent device UUID
  static Future<String> getDeviceId() async {
    final secureStorage = sl<FlutterSecureStorage>();
    String? deviceId = await secureStorage.read(key: _deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await secureStorage.write(key: _deviceIdKey, value: deviceId);
    }
    return deviceId;
  }

  // Update session document in Firestore
  static Future<void> updateSession(String uid) async {
    try {
      final deviceId = await getDeviceId();
      final deviceInfo = DeviceInfoPlugin();
      
      String deviceModel = 'Unknown Device';
      String osVersion = 'Unknown OS';

      if (kIsWeb) {
        deviceModel = 'Web Browser';
        final webInfo = await deviceInfo.webBrowserInfo;
        osVersion = webInfo.userAgent ?? 'Unknown Browser';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = androidInfo.model;
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = iosInfo.name;
        osVersion = 'iOS ${iosInfo.systemVersion}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceModel = macInfo.model;
        osVersion = 'macOS ${macInfo.osRelease}';
      } else if (Platform.isWindows) {
        deviceModel = 'Windows PC';
        osVersion = 'Windows';
      } else if (Platform.isLinux) {
        deviceModel = 'Linux PC';
        osVersion = 'Linux';
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(deviceId)
          .set({
            'deviceId': deviceId,
            'deviceModel': deviceModel,
            'osVersion': osVersion,
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      
      debugPrint('Session updated for device: $deviceId ($deviceModel, $osVersion)');
    } catch (e) {
      debugPrint('Failed to update session: $e');
    }
  }

  // Set up live listener for session revocation
  static Future<void> setupRevocationListener(
    String uid, 
    VoidCallback onRevoked,
  ) async {
    try {
      await _sessionSubscription?.cancel();
      final deviceId = await getDeviceId();

      // Check if current device's session exists first, if it does, listen to it
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(deviceId);
          
      final initialCheck = await docRef.get();
      if (initialCheck.exists) {
        _sessionSubscription = docRef.snapshots().listen((snapshot) {
          if (!snapshot.exists) {
            debugPrint('Session revoked remotely for device ID: $deviceId');
            onRevoked();
          }
        }, onError: (e) {
          debugPrint('Session listener error: $e');
        });
      }
    } catch (e) {
      debugPrint('Failed to setup revocation listener: $e');
    }
  }

  static Future<void> cancelRevocationListener() async {
    await _sessionSubscription?.cancel();
    _sessionSubscription = null;
  }

  // Wipe local database, secure storage, sign out of Firebase, and trigger navigation
  static Future<void> performLocalWipeAndLogout() async {
    await cancelRevocationListener();

    try {
      // 1. Sign out of Firebase Auth
      await fb.FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      // 2. Wipe secure storage keys
      final secureStorage = sl<FlutterSecureStorage>();
      await secureStorage.deleteAll();
      sl<EncryptionService>().clearKey();
    } catch (_) {}

    try {
      // 3. Wipe Isar database
      if (sl.isRegistered<Isar>()) {
        final isar = sl<Isar>();
        await isar.writeTxn(() async {
          await isar.clear();
        });
      }
    } catch (_) {}
  }
}
