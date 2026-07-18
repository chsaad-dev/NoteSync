import 'package:flutter_test/flutter_test.dart';
import 'package:notesync/domain/entities/user_profile.dart';

void main() {
  group('UserProfile Model Mapping and Serialization', () {
    test('should construct UserProfile with default fields', () {
      const profile = UserProfile(
        uid: 'user_123',
        email: 'test@example.com',
        usedStorage: 100,
        maxStorage: 1000,
      );

      expect(profile.uid, equals('user_123'));
      expect(profile.email, equals('test@example.com'));
      expect(profile.displayName, equals(''));
      expect(profile.photoUrl, isNull);
      expect(profile.usedStorage, equals(100));
      expect(profile.maxStorage, equals(1000));
    });

    test('should map fromMap and toMap correctly', () {
      final map = {
        'email': 'jane@example.com',
        'displayName': 'Jane Doe',
        'photoUrl': 'https://cloudinary.com/jane.jpg',
        'usedStorage': 500,
        'maxStorage': 5000,
      };

      final profile = UserProfile.fromMap(map, 'jane_uid');

      expect(profile.uid, equals('jane_uid'));
      expect(profile.email, equals('jane@example.com'));
      expect(profile.displayName, equals('Jane Doe'));
      expect(profile.photoUrl, equals('https://cloudinary.com/jane.jpg'));
      expect(profile.usedStorage, equals(500));
      expect(profile.maxStorage, equals(5000));

      final outputMap = profile.toMap();
      expect(outputMap['email'], equals('jane@example.com'));
      expect(outputMap['displayName'], equals('Jane Doe'));
      expect(outputMap['photoUrl'], equals('https://cloudinary.com/jane.jpg'));
      expect(outputMap['usedStorage'], equals(500));
      expect(outputMap['maxStorage'], equals(5000));
    });

    test('should copyWith correctly', () {
      const profile = UserProfile(
        uid: 'user_123',
        email: 'test@example.com',
        displayName: 'John',
        photoUrl: 'old_url',
        usedStorage: 100,
        maxStorage: 1000,
      );

      final updated = profile.copyWith(
        displayName: 'Johnathan',
        photoUrl: 'new_url',
        usedStorage: 200,
      );

      expect(updated.uid, equals('user_123'));
      expect(updated.email, equals('test@example.com'));
      expect(updated.displayName, equals('Johnathan'));
      expect(updated.photoUrl, equals('new_url'));
      expect(updated.usedStorage, equals(200));
      expect(updated.maxStorage, equals(1000));
    });

    test('should compare equality correctly', () {
      const profile1 = UserProfile(
        uid: 'user_123',
        email: 'test@example.com',
        displayName: 'John',
        photoUrl: 'url',
        usedStorage: 100,
        maxStorage: 1000,
      );

      const profile2 = UserProfile(
        uid: 'user_123',
        email: 'test@example.com',
        displayName: 'John',
        photoUrl: 'url',
        usedStorage: 100,
        maxStorage: 1000,
      );

      expect(profile1, equals(profile2));
      expect(profile1.hashCode, equals(profile2.hashCode));
    });
  });
}
