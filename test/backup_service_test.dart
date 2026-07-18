import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:notesync/core/errors/result.dart';
import 'package:notesync/domain/entities/note_entity.dart';
import 'package:notesync/domain/repository/note_repository.dart';

class FakeNoteRepository implements NoteRepository {
  final List<NoteEntity> notes = [];

  @override
  Future<Result<List<NoteEntity>>> getNotes() async {
    return Success(notes);
  }

  @override
  Future<Result<NoteEntity?>> getNoteById(String noteId) async {
    final match = notes.where((n) => n.noteId == noteId).toList();
    return Success(match.isEmpty ? null : match.first);
  }

  @override
  Future<Result<void>> saveNote(NoteEntity note) async {
    notes.add(note);
    return const Success(null);
  }

  @override
  Stream<List<NoteEntity>> watchNotes() => throw UnimplementedError();
  @override
  Stream<List<NoteEntity>> watchTrash() => throw UnimplementedError();
  @override
  Stream<List<NoteEntity>> watchVault() => throw UnimplementedError();
  @override
  Future<Result<void>> deleteNote(String noteId, {bool permanent = false}) => throw UnimplementedError();
  @override
  Future<Result<void>> syncWithCloud() => throw UnimplementedError();
  @override
  Future<Result<void>> deleteAccount() => throw UnimplementedError();
  @override
  Future<Result<String>> uploadMedia(String filePath) => throw UnimplementedError();
  @override
  Future<Result<void>> deleteMedia(String mediaUrl) => throw UnimplementedError();
  @override
  Future<Result<void>> renameFolder(String oldName, String newName) => throw UnimplementedError();
  @override
  Future<Result<void>> deleteFolder(String folderName, {required bool deleteNotes}) => throw UnimplementedError();
}

void main() {
  group('BackupService Crypto & Model Tests', () {
    late FakeNoteRepository fakeRepository;

    setUp(() {
      fakeRepository = FakeNoteRepository();
    });

    test('Verify PBKDF2 with 600,000 iterations and AES-CBC encrypt/decrypt pipeline', () async {
      // 1. Arrange note
      final note = NoteEntity(
        noteId: 'test-note-id-123',
        title: 'Crypto Test Title',
        body: 'This is the body content containing encrypted information.',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isPinned: false,
        isDeleted: false,
        isSynced: true,
        tags: ['encryption', 'backup'],
        mediaUrls: [],
        ownerId: 'user-999',
      );
      fakeRepository.notes.add(note);

      final password = 'user-selected-encryption-password';
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      // 2. Perform PBKDF2 key derivation with exactly 600,000 iterations
      final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 600000, 32));
      
      final keyBytes = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
      expect(keyBytes.length, 32); // Must produce a 256-bit key

      // 3. Serialize and Encrypt JSON representation of notes list using AES-CBC
      final jsonPayload = json.encode([
        {
          'noteId': note.noteId,
          'title': note.title,
          'body': note.body,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          'isPinned': note.isPinned,
          'isDeleted': note.isDeleted,
          'isSynced': note.isSynced,
          'tags': note.tags,
          'folderId': note.folderId,
          'mediaUrls': note.mediaUrls,
          'ownerId': note.ownerId,
          'isVault': note.isVault,
          'reminderAt': note.reminderAt?.toIso8601String(),
          'isPublic': note.isPublic,
          'publicUrlId': note.publicUrlId,
        }
      ]);

      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(jsonPayload, iv: iv);

      // 4. Decrypt and check equality
      final decryptedText = encrypter.decrypt(encrypted, iv: iv);
      expect(decryptedText, jsonPayload);

      final decryptedList = json.decode(decryptedText) as List<dynamic>;
      expect(decryptedList[0]['noteId'], 'test-note-id-123');
      expect(decryptedList[0]['title'], 'Crypto Test Title');
      expect(decryptedList[0]['body'], 'This is the body content containing encrypted information.');
    });
  });
}
