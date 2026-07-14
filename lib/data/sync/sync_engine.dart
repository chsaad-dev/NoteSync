import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../core/errors/result.dart';
import '../../core/errors/failures.dart';
import '../../core/security/encryption_service.dart';

import '../local/models/isar_note_model.dart';
import '../local/note_local_data_source.dart';
import '../models/firestore_note_model.dart';
import '../remote/note_remote_data_source.dart';
import '../remote/cloudinary_service.dart';

class SyncEngine {
  final NoteLocalDataSource _localDataSource;
  final NoteRemoteDataSource _remoteDataSource;
  final CloudinaryService _cloudinaryService;
  final EncryptionService _encryptionService;
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid = const Uuid();

  SyncEngine({
    required NoteLocalDataSource localDataSource,
    required NoteRemoteDataSource remoteDataSource,
    required CloudinaryService cloudinaryService,
    required EncryptionService encryptionService,
    required firebase_auth.FirebaseAuth firebaseAuth,
    required FlutterSecureStorage secureStorage,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource,
        _cloudinaryService = cloudinaryService,
        _encryptionService = encryptionService,
        _firebaseAuth = firebaseAuth,
        _secureStorage = secureStorage;

  String get _currentUserId => _firebaseAuth.currentUser?.uid ?? '';
  String _lastSyncKey(String uid) => 'last_sync_timestamp_$uid';

  Future<Result<void>> sync() async {
    final uid = _currentUserId;
    if (uid.isEmpty) {
      return FailureResult(const AuthFailure('User not authenticated'));
    }

    try {
      // 1. Push Phase — returns set of noteIds that were successfully pushed
      final pushedNoteIds = await _pushLocalChanges(uid);

      // 2. Pull Phase — skips notes we just pushed to avoid false conflicts
      await _pullRemoteChanges(uid, pushedNoteIds);

      // 3. Purge Phase
      await _purgeDeletedNotes(uid);

      return const Success(null);
    } catch (e) {
      return FailureResult(ServerFailure('Sync failed: $e'));
    }
  }

  Future<Set<String>> _pushLocalChanges(String uid) async {
    final pushedIds = <String>{};
    final unsynced = await _localDataSource.getUnsyncedNotes(uid);
    for (final model in unsynced) {
      try {
        final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
        final entity = model.toEntity(decryptedBody);
        final firestoreModel = FirestoreNoteModel.fromEntity(entity);
        
        await _remoteDataSource.saveNote(uid, firestoreModel);
        pushedIds.add(model.noteId);

        final currentLocal = await _localDataSource.getNoteById(model.noteId);
        if (currentLocal != null && currentLocal.updatedAt.isAtSameMomentAs(model.updatedAt)) {
          currentLocal.isSynced = true;
          await _localDataSource.saveNote(currentLocal);
        }
      } catch (_) {
        // Ignore single failure, continue other notes
      }
    }
    return pushedIds;
  }

  Future<void> _pullRemoteChanges(String uid, Set<String> justPushedIds) async {
    final lastSyncStr = await _secureStorage.read(key: _lastSyncKey(uid));
    final lastSync = lastSyncStr != null
        ? DateTime.parse(lastSyncStr)
        : DateTime.fromMillisecondsSinceEpoch(0);

    final pullTime = DateTime.now();

    final remoteNotes = await _remoteDataSource.getNotesModifiedSince(uid, lastSync);
    for (final remoteNote in remoteNotes) {
      final localModel = await _localDataSource.getNoteById(remoteNote.noteId);
      if (localModel == null) {
        // New note from remote — save locally
        final encrypted = await _encryptionService.encrypt(remoteNote.body);
        final newLocalModel = IsarNoteModel.fromEntity(
          entity: remoteNote.toEntity(),
          encryptedBody: encrypted.encryptedBase64,
          iv: encrypted.ivBase64,
        );
        await _localDataSource.saveNote(newLocalModel);
      } else {
        // Note exists locally

        // If we just pushed this note in this sync cycle, skip conflict
        // detection — the remote version is what we just uploaded.
        if (justPushedIds.contains(remoteNote.noteId)) {
          // Just mark local as synced and move on
          localModel.isSynced = true;
          await _localDataSource.saveNote(localModel);
          continue;
        }

        final bool localChanged = !localModel.isSynced;
        
        if (localChanged) {
          // Local has unsaved changes AND remote has changes.
          // Check if the content is actually different before creating a conflict.
          final localDecrypted = await _encryptionService.decrypt(localModel.encryptedBody, localModel.iv);
          final bool sameContent = localModel.title == remoteNote.title &&
              localDecrypted == remoteNote.body &&
              localModel.isDeleted == remoteNote.isDeleted &&
              localModel.isPinned == remoteNote.isPinned;

          if (sameContent) {
            // Content is identical — just mark as synced, no conflict needed
            localModel.isSynced = true;
            await _localDataSource.saveNote(localModel);
          } else {
            // Genuine conflict: local and remote have DIFFERENT content.
            // Last-write-wins: keep the newer version, save older as conflict copy.
            if (remoteNote.updatedAt.isAfter(localModel.updatedAt)) {
              // Remote is newer — save local as conflict copy, overwrite local with remote
              final conflictNote = localModel.toEntity(localDecrypted).copyWith(
                noteId: _uuid.v4(),
                title: '${localModel.title} (conflict copy)',
                updatedAt: DateTime.now(),
                isSynced: false,
              );
              final encryptedConflict = await _encryptionService.encrypt(conflictNote.body);
              final conflictModel = IsarNoteModel.fromEntity(
                entity: conflictNote,
                encryptedBody: encryptedConflict.encryptedBase64,
                iv: encryptedConflict.ivBase64,
              );
              await _localDataSource.saveNote(conflictModel);

              final encryptedRemote = await _encryptionService.encrypt(remoteNote.body);
              final updatedLocal = IsarNoteModel.fromEntity(
                entity: remoteNote.toEntity(),
                encryptedBody: encryptedRemote.encryptedBase64,
                iv: encryptedRemote.ivBase64,
              );
              await _localDataSource.saveNote(updatedLocal);
            }
            // else: local is newer — it will be pushed in the next sync cycle
          }
        } else {
          // Local is already synced — overwrite with remote version
          final encrypted = await _encryptionService.encrypt(remoteNote.body);
          final updatedLocal = IsarNoteModel.fromEntity(
            entity: remoteNote.toEntity(),
            encryptedBody: encrypted.encryptedBase64,
            iv: encrypted.ivBase64,
          );
          await _localDataSource.saveNote(updatedLocal);
        }
      }
    }

    await _secureStorage.write(key: _lastSyncKey(uid), value: pullTime.toIso8601String());
  }

  Future<void> _purgeDeletedNotes(String uid) async {
    final cutOff = DateTime.now().subtract(const Duration(days: 30));
    final oldDeletedNotes = await _localDataSource.getDeletedNotesOlderThan(uid, cutOff);
    
    if (oldDeletedNotes.isEmpty) return;

    final List<String> idsToPurge = [];
    final token = await _firebaseAuth.currentUser?.getIdToken() ?? '';

    for (final model in oldDeletedNotes) {
      idsToPurge.add(model.noteId);
      for (final url in model.mediaUrls) {
        try {
          await _cloudinaryService.deleteMedia(url, token);
        } catch (_) {}
      }
      try {
        await _remoteDataSource.deleteNote(uid, model.noteId);
      } catch (_) {}
    }

    await _localDataSource.hardDeleteNotes(idsToPurge);
  }
}
