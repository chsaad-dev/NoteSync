import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:notesync/core/security/encryption_service.dart';
import 'package:notesync/data/local/note_local_data_source.dart';
import 'package:notesync/data/local/models/isar_note_model.dart';
import 'package:notesync/data/remote/note_remote_data_source.dart';
import 'package:notesync/data/remote/cloudinary_service.dart';
import 'package:notesync/data/repository/note_repository_impl.dart';
import 'package:notesync/domain/entities/note_entity.dart';
import 'package:notesync/data/models/firestore_note_model.dart';

class MockLocalDataSource extends Mock implements NoteLocalDataSource {}
class MockRemoteDataSource extends Mock implements NoteRemoteDataSource {}
class MockCloudinaryService extends Mock implements CloudinaryService {}
class MockEncryptionService extends Mock implements EncryptionService {}
class MockFirebaseAuth extends Mock implements firebase_auth.FirebaseAuth {}
class MockUser extends Mock implements firebase_auth.User {}
class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late MockLocalDataSource mockLocal;
  late MockRemoteDataSource mockRemote;
  late MockCloudinaryService mockCloudinary;
  late MockEncryptionService mockEncryption;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockConnectivity mockConnectivity;
  late NoteRepositoryImpl repository;

  setUp(() {
    mockLocal = MockLocalDataSource();
    mockRemote = MockRemoteDataSource();
    mockCloudinary = MockCloudinaryService();
    mockEncryption = MockEncryptionService();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockConnectivity = MockConnectivity();

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('user123');

    repository = NoteRepositoryImpl(
      localDataSource: mockLocal,
      remoteDataSource: mockRemote,
      cloudinaryService: mockCloudinary,
      encryptionService: mockEncryption,
      firebaseAuth: mockAuth,
      connectivity: mockConnectivity,
    );

    registerFallbackValue(IsarNoteModel());
    registerFallbackValue(FirestoreNoteModel(
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

  group('NoteRepositoryImpl CRUD Tests', () {
    test('saveNote should encrypt and save to Isar immediately without blocking on network', () async {
      final note = NoteEntity(
        noteId: 'note_123',
        title: 'Draft Title',
        body: 'Draft body contents',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isPinned: false,
        isDeleted: false,
        isSynced: false,
        tags: [],
        mediaUrls: [],
        ownerId: 'user123',
      );

      when(() => mockEncryption.encrypt(any())).thenAnswer((_) async => const EncryptedData(
        encryptedBase64: 'enc_body_b64',
        ivBase64: 'iv_b64',
      ));

      when(() => mockLocal.saveNote(any())).thenAnswer((_) async => {});

      when(() => mockConnectivity.checkConnectivity()).thenAnswer((_) async => [ConnectivityResult.none]);

      final result = await repository.saveNote(note);

      expect(result.isSuccess, isTrue);

      verify(() => mockLocal.saveNote(any())).called(1);
      
      verifyNever(() => mockRemote.saveNote(any(), any()));
    });
  });
}
