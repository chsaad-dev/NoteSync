import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:notesync/core/security/encryption_service.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage mockSecureStorage;
  late EncryptionService encryptionService;
  late Map<String, String> secureStorageMap;

  setUp(() {
    mockSecureStorage = MockSecureStorage();
    secureStorageMap = {};

    when(() => mockSecureStorage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return secureStorageMap[key];
    });

    when(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String;
      secureStorageMap[key] = value;
    });

    encryptionService = EncryptionService(mockSecureStorage);
  });

  group('EncryptionService Tests', () {
    test('should encrypt and decrypt note body correctly', () async {
      const originalText = 'This is a secure offline note content.';

      final encryptedData = await encryptionService.encrypt(originalText);

      expect(encryptedData.encryptedBase64, isNotEmpty);
      expect(encryptedData.ivBase64, isNotEmpty);
      expect(encryptedData.encryptedBase64, isNot(equals(originalText)));

      final decryptedText = await encryptionService.decrypt(
        encryptedData.encryptedBase64,
        encryptedData.ivBase64,
      );

      expect(decryptedText, equals(originalText));
    });

    test('should persist key and reuse it for subsequent calls', () async {
      const first = 'First note body';
      const second = 'Second note body';

      final enc1 = await encryptionService.encrypt(first);
      final firstKey = secureStorageMap['notesync_aes_key'];
      expect(firstKey, isNotNull);

      final enc2 = await encryptionService.encrypt(second);
      final secondKey = secureStorageMap['notesync_aes_key'];
      expect(secondKey, equals(firstKey));

      final dec1 = await encryptionService.decrypt(enc1.encryptedBase64, enc1.ivBase64);
      final dec2 = await encryptionService.decrypt(enc2.encryptedBase64, enc2.ivBase64);

      expect(dec1, equals(first));
      expect(dec2, equals(second));
    });
  });
}
