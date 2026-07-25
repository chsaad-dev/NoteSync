import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

class EncryptionService {
  final FlutterSecureStorage _secureStorage;
  static const String _keyAlias = 'notesync_aes_key';
  static const int _blockSize = 16;
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

  /// Applies PKCS7 padding so the byte length is a multiple of [_blockSize].
  /// For an empty input this produces a full 16-byte padding block (each byte = 0x10).
  Uint8List _applyPkcs7Padding(List<int> data) {
    final padLength = _blockSize - (data.length % _blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setAll(0, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  /// Strips PKCS7 padding from decrypted bytes.
  /// Returns the original plaintext bytes.
  Uint8List _removePkcs7Padding(List<int> data) {
    if (data.isEmpty) return Uint8List(0);
    final padLength = data.last;
    if (padLength < 1 || padLength > _blockSize || padLength > data.length) {
      return Uint8List.fromList(data);
    }
    // Verify all padding bytes match
    for (var i = data.length - padLength; i < data.length; i++) {
      if (data[i] != padLength) {
        return Uint8List.fromList(data); // Invalid padding, return as-is
      }
    }
    return Uint8List.fromList(data.sublist(0, data.length - padLength));
  }

  Future<EncryptedData> encrypt(String plaintext) async {
    try {
      final key = await _getOrCreateKey();
      final iv = encrypt_pkg.IV.fromSecureRandom(16);

      // Manual PKCS7 padding to work around encrypt package bug with
      // empty/short inputs in CBC mode (RangeError on inputs < 16 bytes).
      final plaintextBytes = utf8.encode(plaintext);
      final paddedBytes = _applyPkcs7Padding(plaintextBytes);

      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc, padding: null),
      );
      final encrypted = encrypter.encryptBytes(paddedBytes.toList(), iv: iv);

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

      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc, padding: null),
      );
      final decryptedBytes = encrypter.decryptBytes(
        encrypt_pkg.Encrypted.fromBase64(encryptedBase64),
        iv: iv,
      );

      final unpaddedBytes = _removePkcs7Padding(decryptedBytes);
      return utf8.decode(unpaddedBytes);
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
