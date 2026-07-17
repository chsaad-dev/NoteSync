import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/note_entity.dart';
import '../../domain/repository/note_repository.dart';
import '../di/injection_container.dart';

class BackupSummary {
  final int imported;
  final int skipped;

  const BackupSummary({required this.imported, required this.skipped});
}

class BackupService {
  final NoteRepository _noteRepository;

  BackupService(this._noteRepository);

  // Derive 256-bit key from password using PBKDF2 with SHA-256 (600,000 iterations)
  Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 600000, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  // Export all notes as a password-encrypted ZIP archive
  Future<void> exportBackup(String password) async {
    // 1. Generate 16-byte random salt
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));

    // 2. Derive key from password
    final keyBytes = _deriveKey(password, salt);

    // 3. Fetch all local notes
    final result = await _noteRepository.getNotes();
    final List<NoteEntity> notes = result.fold(
      (notesList) => notesList,
      (_) => throw Exception('Failed to retrieve notes from database'),
    );

    if (notes.isEmpty) {
      throw Exception('No notes found to backup');
    }

    // 4. Serialize notes to JSON
    final jsonList = notes.map((note) => {
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
    }).toList();
    
    final jsonStr = json.encode(jsonList);

    // 5. Encrypt JSON payload using AES-256-CBC
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);

    // 6. Bundle into ZIP
    final archive = Archive();
    archive.addFile(ArchiveFile('salt.bin', salt.length, salt));
    archive.addFile(ArchiveFile('iv.bin', iv.bytes.length, iv.bytes));
    archive.addFile(ArchiveFile('backup.enc', encrypted.bytes.length, encrypted.bytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Failed to generate ZIP archive');
    }

    // 7. Write to temp directory and trigger sharing
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/notesync_backup.zip');
    await file.writeAsBytes(zipBytes);

    await Share.shareXFiles([XFile(file.path)], subject: 'NoteSync Encrypted Backup');
  }

  // Import notes from a password-encrypted ZIP archive
  Future<BackupSummary> importBackup(String filePath, String password, {bool overwriteConflicts = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file does not exist');
    }

    final zipBytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // 1. Extract files from ZIP
    final saltFile = archive.findFile('salt.bin');
    final ivFile = archive.findFile('iv.bin');
    final encFile = archive.findFile('backup.enc');

    if (saltFile == null || ivFile == null || encFile == null) {
      throw Exception('Invalid backup file structure: missing required security parameters.');
    }

    final salt = saltFile.content as List<int>;
    final ivBytes = ivFile.content as List<int>;
    final encryptedBytes = encFile.content as List<int>;

    // 2. Derive key
    final keyBytes = _deriveKey(password, Uint8List.fromList(salt));

    // 3. Decrypt payload
    String decryptedJson;
    try {
      final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
      final encrypted = enc.Encrypted(Uint8List.fromList(encryptedBytes));
      decryptedJson = encrypter.decrypt(encrypted, iv: enc.IV(Uint8List.fromList(ivBytes)));
    } catch (_) {
      throw Exception('Decryption failed. Please make sure the password is correct.');
    }

    // 4. Parse JSON and upsert notes
    final List<dynamic> jsonList = json.decode(decryptedJson) as List<dynamic>;
    int importedCount = 0;
    int skippedCount = 0;

    for (final item in jsonList) {
      final noteMap = item as Map<String, dynamic>;
      final noteId = noteMap['noteId'] as String;

      final existingCheck = await _noteRepository.getNoteById(noteId);
      final exists = existingCheck.fold((existingNote) => existingNote != null, (_) => false);

      if (exists && !overwriteConflicts) {
        skippedCount++;
        continue;
      }

      final note = NoteEntity(
        noteId: noteId,
        title: noteMap['title'] as String? ?? '',
        body: noteMap['body'] as String? ?? '',
        createdAt: DateTime.parse(noteMap['createdAt'] as String),
        updatedAt: DateTime.parse(noteMap['updatedAt'] as String),
        isPinned: noteMap['isPinned'] as bool? ?? false,
        isDeleted: noteMap['isDeleted'] as bool? ?? false,
        isSynced: noteMap['isSynced'] as bool? ?? false,
        tags: List<String>.from(noteMap['tags'] ?? []),
        folderId: noteMap['folderId'] as String?,
        mediaUrls: List<String>.from(noteMap['mediaUrls'] ?? []),
        ownerId: noteMap['ownerId'] as String? ?? '',
        isVault: noteMap['isVault'] as bool? ?? false,
        reminderAt: noteMap['reminderAt'] != null ? DateTime.parse(noteMap['reminderAt'] as String) : null,
        isPublic: noteMap['isPublic'] as bool? ?? false,
        publicUrlId: noteMap['publicUrlId'] as String?,
      );

      final saveResult = await _noteRepository.saveNote(note);
      saveResult.fold(
        (_) => importedCount++,
        (failure) => throw Exception('Failed to save note: ${failure.message}'),
      );
    }

    return BackupSummary(imported: importedCount, skipped: skippedCount);
  }
}
