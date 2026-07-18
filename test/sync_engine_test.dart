import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:notesync/core/security/encryption_service.dart';
import 'package:notesync/data/local/note_local_data_source.dart';
import 'package:notesync/data/local/models/isar_note_model.dart';
import 'package:notesync/data/remote/note_remote_data_source.dart';
import 'package:notesync/data/remote/cloudinary_service.dart';
import 'package:notesync/data/models/firestore_note_model.dart';
import 'package:notesync/data/sync/sync_engine.dart';
import 'package:notesync/domain/entities/note_entity.dart';

class MockLocalDataSource extends Mock implements NoteLocalDataSource {}
class MockRemoteDataSource extends Mock implements NoteRemoteDataSource {}
class MockCloudinaryService extends Mock implements CloudinaryService {}
class MockEncryptionService extends Mock implements EncryptionService {}
class MockFirebaseAuth extends Mock implements firebase_auth.FirebaseAuth {}
class MockUser extends Mock implements firebase_auth.User {}
class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockLocalDataSource mockLocal;
  late MockRemoteDataSource mockRemote;
  late MockCloudinaryService mockCloudinary;
  late MockEncryptionService mockEncryption;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockSecureStorage mockSecure;
  late SyncEngine syncEngine;

  setUp(() {
    mockLocal = MockLocalDataSource();
    mockRemote = MockRemoteDataSource();
    mockCloudinary = MockCloudinaryService();
    mockEncryption = MockEncryptionService();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockSecure = MockSecureStorage();

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('user123');
    when(() => mockUser.getIdToken()).thenAnswer((_) async => 'mock_token');

    syncEngine = SyncEngine(
      localDataSource: mockLocal,
      remoteDataSource: mockRemote,
      cloudinaryService: mockCloudinary,
      encryptionService: mockEncryption,
      firebaseAuth: mockAuth,
      secureStorage: mockSecure,
    );

    registerFallbackValue(IsarNoteModel());
    registerFallbackValue(NoteEntity(
      noteId: '',
      title: '',
      body: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isPinned: false,
      isDeleted: false,
      isSynced: false,
      tags: const [],
      mediaUrls: const [],
      ownerId: '',
    ));
  });

  group('SyncEngine Conflict Resolution Tests', () {
    test('LWW: should overwrite local note when remote note is newer by > 5 seconds', () async {
      final now = DateTime.now();
      final localUpdatedAt = now.subtract(const Duration(seconds: 10));
      final remoteUpdatedAt = now;

      when(() => mockSecure.read(key: any(named: 'key'))).thenAnswer((_) async => localUpdatedAt.toIso8601String());
      when(() => mockSecure.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});

      when(() => mockEncryption.encrypt(any())).thenAnswer((_) async => const EncryptedData(
        encryptedBase64: 'enc_body',
        ivBase64: 'iv_val',
      ));

      when(() => mockLocal.getUnsyncedNotes(any())).thenAnswer((_) async => []);

      final remoteNote = FirestoreNoteModel(
        noteId: 'note_1',
        title: 'Remote Title',
        body: 'Remote Plain Content',
        createdAt: localUpdatedAt,
        updatedAt: remoteUpdatedAt,
        isPinned: false,
        isDeleted: false,
        isSynced: true,
        tags: [],
        mediaUrls: [],
        ownerId: 'user123',
      );
      when(() => mockRemote.getNotesModifiedSince(any(), any())).thenAnswer((_) async => [remoteNote]);

      final localIsarModel = IsarNoteModel()
        ..noteId = 'note_1'
        ..title = 'Local Title'
        ..encryptedBody = 'local_enc'
        ..iv = 'local_iv'
        ..createdAt = localUpdatedAt
        ..updatedAt = localUpdatedAt
        ..isPinned = false;
      localIsarModel.isSynced = true; 
      localIsarModel.isDeleted = false;
      localIsarModel.isVault = false;
      localIsarModel.isPublic = false;
      localIsarModel.publicUrlId = null;
      localIsarModel.tags = [];
      localIsarModel.mediaUrls = [];
      localIsarModel.ownerId = 'user123';

      when(() => mockLocal.getNoteById('note_1', any())).thenAnswer((_) async => localIsarModel);
      when(() => mockLocal.saveNote(any())).thenAnswer((_) async {});

      await syncEngine.sync();

      final captured = verify(() => mockLocal.saveNote(captureAny())).captured;
      expect(captured.length, equals(1));
      final savedModel = captured.first as IsarNoteModel;
      expect(savedModel.noteId, equals('note_1'));
      expect(savedModel.title, equals('Remote Title'));
    });

    test('Conflict Copy: should create conflict copy when timestamps are within 5 seconds', () async {
      final now = DateTime.now();
      final localUpdatedAt = now.subtract(const Duration(seconds: 2));
      final remoteUpdatedAt = now;

      when(() => mockSecure.read(key: any(named: 'key'))).thenAnswer((_) async => localUpdatedAt.toIso8601String());
      when(() => mockSecure.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});

      when(() => mockEncryption.decrypt(any(), any())).thenAnswer((_) async => 'Local plain text');
      when(() => mockEncryption.encrypt(any())).thenAnswer((_) async => const EncryptedData(
        encryptedBase64: 'conflict_enc',
        ivBase64: 'conflict_iv',
      ));

      when(() => mockLocal.getUnsyncedNotes(any())).thenAnswer((_) async => []);

      final remoteNote = FirestoreNoteModel(
        noteId: 'note_1',
        title: 'Remote Title',
        body: 'Remote Content',
        createdAt: localUpdatedAt,
        updatedAt: remoteUpdatedAt,
        isPinned: false,
        isDeleted: false,
        isSynced: true,
        tags: [],
        mediaUrls: [],
        ownerId: 'user123',
      );
      when(() => mockRemote.getNotesModifiedSince(any(), any())).thenAnswer((_) async => [remoteNote]);

      final localIsarModel = IsarNoteModel()
        ..id = 1
        ..noteId = 'note_1'
        ..title = 'Local Title'
        ..encryptedBody = 'local_enc'
        ..iv = 'local_iv'
        ..createdAt = localUpdatedAt
        ..updatedAt = localUpdatedAt
        ..isPinned = false;
      localIsarModel.isSynced = false; 
      localIsarModel.isDeleted = false;
      localIsarModel.isVault = false;
      localIsarModel.isPublic = false;
      localIsarModel.publicUrlId = null;
      localIsarModel.tags = [];
      localIsarModel.mediaUrls = [];
      localIsarModel.ownerId = 'user123';

      when(() => mockLocal.getNoteById('note_1', any())).thenAnswer((_) async => localIsarModel);
      when(() => mockLocal.saveNote(any())).thenAnswer((_) async {});

      await syncEngine.sync();

      final savedModels = verify(() => mockLocal.saveNote(captureAny())).captured.cast<IsarNoteModel>();
      
      expect(savedModels.length, equals(2));
      
      final conflictCopy = savedModels.firstWhere((m) => m.noteId != 'note_1');
      expect(conflictCopy.title, equals('Local Title (conflict copy)'));
      
      final originalIdUpdate = savedModels.firstWhere((m) => m.noteId == 'note_1');
      expect(originalIdUpdate.title, equals('Remote Title'));
    });
  });
}
