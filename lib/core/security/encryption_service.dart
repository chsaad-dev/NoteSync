import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

class EncryptionService {
  final FlutterSecureStorage _secureStorage;
  static const String _keyAlias = 'notesync_aes_key';
  encrypt_pkg.Key? _cachedKey;

  EncryptionService(this._secureStorage);

  Future<encrypt_pkg.Key> _getOrCreateKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final existingKeyB64 = await _secureStorage.read(key: _keyAlias);
    if (existingKeyB64 != null) {
      try {
        final keyBytes = base64.decode(existingKeyB64);
        _cachedKey = encrypt_pkg.Key(keyBytes);
        return _cachedKey!;
      } catch (_) {
        // Fall through to regeneration if decoding fails
      }
    }

    // Generate new 256-bit key
    final random = Random.secure();
    final keyBytes = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    final newKeyB64 = base64.encode(keyBytes);
    await _secureStorage.write(key: _keyAlias, value: newKeyB64);
    _cachedKey = encrypt_pkg.Key(keyBytes);
    return _cachedKey!;
  }

  Future<EncryptedData> encrypt(String plaintext) async {
    try {
      final key = await _getOrCreateKey();
      final iv = encrypt_pkg.IV.fromSecureRandom(16);
      final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
      
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      return EncryptedData(
        encryptedBase64: encrypted.base64,
        ivBase64: iv.base64,
      );
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  Future<String> decrypt(String encryptedBase64, String ivBase64) async {
    try {
      final key = await _getOrCreateKey();
      final iv = encrypt_pkg.IV.fromBase64(ivBase64);
      final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
      
      final decrypted = encrypter.decrypt64(encryptedBase64, iv: iv);
      return decrypted;
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  Future<void> clearKey() async {
    _cachedKey = null;
    await _secureStorage.delete(key: _keyAlias);
  }
}

class EncryptedData {
  final String encryptedBase64;
  final String ivBase64;

  const EncryptedData({
    required this.encryptedBase64,
    required this.ivBase64,
  });
}
