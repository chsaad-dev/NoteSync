import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:isar/isar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:notesync/core/di/injection_container.dart';
import 'package:notesync/domain/entities/note_entity.dart';
import 'package:notesync/domain/repository/note_repository.dart';
import 'package:notesync/domain/usecases/watch_notes.dart';
import 'package:notesync/domain/usecases/watch_vault_notes.dart';
import 'package:notesync/presentation/providers/auth_provider.dart';
import 'package:notesync/presentation/providers/notes_provider.dart';
import 'package:notesync/presentation/providers/sync_provider.dart';
import 'package:notesync/data/sync/sync_engine.dart';
import 'package:notesync/core/security/encryption_service.dart';

class MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}
class MockUser extends Mock implements fb.User {}
class MockNoteRepository extends Mock implements NoteRepository {}
class MockWatchNotes extends Mock implements WatchNotes {}
class MockWatchVaultNotes extends Mock implements WatchVaultNotes {}
class MockSyncEngine extends Mock implements SyncEngine {}
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}
class MockIsar extends Mock implements Isar {}
class MockEncryptionService extends Mock implements EncryptionService {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockUser mockUserA;
  late MockUser mockUserB;
  late MockNoteRepository mockRepo;
  late MockWatchNotes mockWatchNotes;
  late MockWatchVaultNotes mockWatchVault;
  late MockSyncEngine mockSyncEngine;
  late MockFlutterSecureStorage mockSecure;
  late MockIsar mockIsar;
  late MockEncryptionService mockEncryption;

  setUpAll(() {
    registerFallbackValue(AuthState);
  });

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockUserA = MockUser();
    mockUserB = MockUser();
    mockRepo = MockNoteRepository();
    mockWatchNotes = MockWatchNotes();
    mockWatchVault = MockWatchVaultNotes();
    mockSyncEngine = MockSyncEngine();
    mockSecure = MockFlutterSecureStorage();
    mockIsar = MockIsar();
    mockEncryption = MockEncryptionService();

    when(() => mockUserA.uid).thenReturn('userA');
    when(() => mockUserB.uid).thenReturn('userB');
    when(() => mockUserA.getIdToken(any())).thenAnswer((_) async => 'tokenA');
    when(() => mockUserB.getIdToken(any())).thenAnswer((_) async => 'tokenB');

    // Setup dependency injection mappings
    sl.reset();
    sl.registerSingleton<fb.FirebaseAuth>(mockAuth);
    sl.registerSingleton<NoteRepository>(mockRepo);
    sl.registerSingleton<WatchNotes>(mockWatchNotes);
    sl.registerSingleton<WatchVaultNotes>(mockWatchVault);
    sl.registerSingleton<SyncEngine>(mockSyncEngine);
    sl.registerSingleton<FlutterSecureStorage>(mockSecure);
    sl.registerSingleton<Isar>(mockIsar);
    sl.registerSingleton<EncryptionService>(mockEncryption);

    // Default mock behaviors
    when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(null));
    when(() => mockAuth.signOut()).thenAnswer((_) async {});
    when(() => mockSecure.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    when(() => mockSecure.read(key: any(named: 'key'))).thenAnswer((_) async => 'mock_device_id');
    when(() => mockSecure.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
    when(() => mockIsar.writeTxn(any())).thenAnswer((inv) async {
      final callback = inv.positionalArguments[0] as Future<void> Function();
      await callback();
    });
    when(() => mockIsar.clear()).thenAnswer((_) async {});
    when(() => mockEncryption.clearKey()).thenAnswer((_) async {});
    when(() => mockSyncEngine.cancelSync()).thenAnswer((_) {});
  });

  test('Switching to empty account: login as user A, logout, login as user B (empty)', () async {
    // 1. Initial State
    final controller = StreamController<fb.User?>();
    when(() => mockAuth.authStateChanges()).thenAnswer((_) => controller.stream);
    when(() => mockAuth.currentUser).thenReturn(null);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Verify initial states
    expect(container.read(userIdProvider), isNull);

    // 2. Log in as User A
    when(() => mockAuth.currentUser).thenReturn(mockUserA);
    final userANotes = [
      NoteEntity(
        noteId: '1',
        title: 'User A Note',
        body: 'Hello',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isPinned: false,
        isDeleted: false,
        isSynced: true,
        tags: const [],
        mediaUrls: const [],
        ownerId: 'userA',
      ),
    ];
    when(() => mockWatchNotes()).thenAnswer((_) => Stream.value(userANotes));

    controller.add(mockUserA);
    // Wait for auth provider to emit Authenticated
    await expectLater(
      container.read(authProvider.notifier).stream.firstWhere((s) => s is Authenticated),
      completion(isA<Authenticated>()),
    );

    expect(container.read(userIdProvider), equals('userA'));
    while (container.read(notesStreamProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(notesStreamProvider).value?.length, equals(1));
    expect(container.read(notesStreamProvider).value?.first.title, equals('User A Note'));

    // 3. Logout (sign out sequence checks)
    when(() => mockAuth.signOut()).thenAnswer((_) async {
      controller.add(null);
      when(() => mockAuth.currentUser).thenReturn(null);
    });
    await container.read(authProvider.notifier).signOut();

    expect(container.read(userIdProvider), isNull);
    while (container.read(notesStreamProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(notesStreamProvider).value, isEmpty);

    // 4. Log in as User B (Empty account)
    when(() => mockAuth.currentUser).thenReturn(mockUserB);
    when(() => mockWatchNotes()).thenAnswer((_) => Stream.value(<NoteEntity>[]));

    controller.add(mockUserB);
    await expectLater(
      container.read(authProvider.notifier).stream.firstWhere((s) => s is Authenticated),
      completion(isA<Authenticated>()),
    );

    expect(container.read(userIdProvider), equals('userB'));
    while (container.read(notesStreamProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(notesStreamProvider).value, isEmpty); // Empty account shows no stale notes!
  });

  test('Re-sign in as same user: login as user A, logout, login as user A again', () async {
    final controller = StreamController<fb.User?>();
    when(() => mockAuth.authStateChanges()).thenAnswer((_) => controller.stream);
    when(() => mockAuth.currentUser).thenReturn(null);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 1. Login as User A
    when(() => mockAuth.currentUser).thenReturn(mockUserA);
    final userANotes = [
      NoteEntity(
        noteId: '1',
        title: 'User A Note',
        body: 'Hello',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isPinned: false,
        isDeleted: false,
        isSynced: true,
        tags: const [],
        mediaUrls: const [],
        ownerId: 'userA',
      ),
    ];
    when(() => mockWatchNotes()).thenAnswer((_) => Stream.value(userANotes));

    controller.add(mockUserA);
    await expectLater(
      container.read(authProvider.notifier).stream.firstWhere((s) => s is Authenticated),
      completion(isA<Authenticated>()),
    );

    expect(container.read(userIdProvider), equals('userA'));
    while (container.read(notesStreamProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(notesStreamProvider).value?.length, equals(1));

    // 2. Logout (asserting clean wipe)
    when(() => mockAuth.signOut()).thenAnswer((_) async {
      controller.add(null);
      when(() => mockAuth.currentUser).thenReturn(null);
    });
    await container.read(authProvider.notifier).signOut();

    expect(container.read(userIdProvider), isNull);

    // 3. Login as User A again
    when(() => mockAuth.currentUser).thenReturn(mockUserA);
    when(() => mockWatchNotes()).thenAnswer((_) => Stream.value(userANotes));

    controller.add(mockUserA);
    await expectLater(
      container.read(authProvider.notifier).stream.firstWhere((s) => s is Authenticated),
      completion(isA<Authenticated>()),
    );

    expect(container.read(userIdProvider), equals('userA'));
    while (container.read(notesStreamProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(notesStreamProvider).value?.length, equals(1));
    expect(container.read(notesStreamProvider).value?.first.title, equals('User A Note'));
  });
}
