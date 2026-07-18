import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/errors/failures.dart';
import '../../core/errors/result.dart';
import '../../core/security/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/di/injection_container.dart';
import '../../domain/entities/note_entity.dart';
import '../../domain/repository/note_repository.dart';
import '../local/models/isar_note_model.dart';
import '../local/note_local_data_source.dart';
import '../remote/cloudinary_service.dart';
import '../remote/note_remote_data_source.dart';

class NoteRepositoryImpl implements NoteRepository {
  final NoteLocalDataSource _localDataSource;
  final NoteRemoteDataSource _remoteDataSource;
  final CloudinaryService _cloudinaryService;
  final EncryptionService _encryptionService;
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final Connectivity _connectivity;
  
  // Callback or injector for the SyncEngine to avoid circular dependency.
  // We will assign this during initialization.
  Future<Result<void>> Function()? syncEngineTrigger;

  NoteRepositoryImpl({
    required NoteLocalDataSource localDataSource,
    required NoteRemoteDataSource remoteDataSource,
    required CloudinaryService cloudinaryService,
    required EncryptionService encryptionService,
    required firebase_auth.FirebaseAuth firebaseAuth,
    required Connectivity connectivity,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource,
        _cloudinaryService = cloudinaryService,
        _encryptionService = encryptionService,
        _firebaseAuth = firebaseAuth,
        _connectivity = connectivity;

  String get _currentUserId => _firebaseAuth.currentUser?.uid ?? '';

  Future<String> _getIdToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return await user.getIdToken() ?? '';
  }

  @override
  Stream<List<NoteEntity>> watchNotes() {
    return _localDataSource.watchNotes(_currentUserId).asyncMap((models) async {
      final entities = <NoteEntity>[];
      for (final model in models) {
        try {
          final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
          entities.add(model.toEntity(decryptedBody));
        } catch (_) {
          entities.add(model.toEntity('[Decryption Error: Check Key]'));
        }
      }
      return entities;
    });
  }

  @override
  Stream<List<NoteEntity>> watchTrash() {
    return _localDataSource.watchTrash(_currentUserId).asyncMap((models) async {
      final entities = <NoteEntity>[];
      for (final model in models) {
        try {
          final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
          entities.add(model.toEntity(decryptedBody));
        } catch (_) {
          entities.add(model.toEntity('[Decryption Error: Check Key]'));
        }
      }
      return entities;
    });
  }

  @override
  Stream<List<NoteEntity>> watchVault() {
    return _localDataSource.watchVault(_currentUserId).asyncMap((models) async {
      final entities = <NoteEntity>[];
      for (final model in models) {
        try {
          final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
          entities.add(model.toEntity(decryptedBody));
        } catch (_) {
          entities.add(model.toEntity('[Decryption Error: Check Key]'));
        }
      }
      return entities;
    });
  }

  @override
  Future<Result<List<NoteEntity>>> getNotes() async {
    try {
      final models = await _localDataSource.getNotes(_currentUserId);
      final entities = <NoteEntity>[];
      for (final model in models) {
        final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
        entities.add(model.toEntity(decryptedBody));
      }
      return Success(entities);
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<NoteEntity?>> getNoteById(String noteId) async {
    try {
      final model = await _localDataSource.getNoteById(noteId, _currentUserId);
      if (model == null) return const Success(null);
      final decryptedBody = await _encryptionService.decrypt(model.encryptedBody, model.iv);
      return Success(model.toEntity(decryptedBody));
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> saveNote(NoteEntity note) async {
    try {
      final encryptedData = await _encryptionService.encrypt(note.body);
      
      final localModel = IsarNoteModel.fromEntity(
        entity: note.copyWith(isSynced: false, ownerId: _currentUserId),
        encryptedBody: encryptedData.encryptedBase64,
        iv: encryptedData.ivBase64,
      );

      await _localDataSource.saveNote(localModel);
      _triggerSyncAsynchronously();

      return const Success(null);
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteNote(String noteId, {bool permanent = false}) async {
    try {
      if (permanent) {
        final noteResult = await getNoteById(noteId);
        if (noteResult.isSuccess) {
          final note = noteResult.orThrow;
          if (note != null) {
            for (final url in note.mediaUrls) {
              await deleteMedia(url);
            }
            final isConnected = await _isConnected();
            if (isConnected) {
              await _remoteDataSource.deleteNote(_currentUserId, noteId);
            }
          }
        }
        await _localDataSource.deleteNote(noteId, _currentUserId);
      } else {
        final model = await _localDataSource.getNoteById(noteId, _currentUserId);
        if (model != null) {
          model.isDeleted = true;
          model.isSynced = false;
          model.updatedAt = DateTime.now();
          await _localDataSource.saveNote(model);
          _triggerSyncAsynchronously();
        }
      }
      return const Success(null);
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<String>> uploadMedia(String filePath) async {
    try {
      final connected = await _isConnected();
      if (!connected) {
        return const FailureResult(ServerFailure('No internet connection. Please check your network and try again.'));
      }
      final token = await _getIdToken();
      final url = await _cloudinaryService.uploadMedia(filePath, token);
      return Success(url);
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
        return const FailureResult(ServerFailure('No internet connection. Please check your network and try again.'));
      }
      return FailureResult(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteMedia(String mediaUrl) async {
    try {
      final token = await _getIdToken();
      await _cloudinaryService.deleteMedia(mediaUrl, token);
      return const Success(null);
    } catch (e) {
      return FailureResult(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteAccount() async {
    try {
      final token = await _getIdToken();
      final uid = _currentUserId;
      await _remoteDataSource.deleteAccountOnWorker(token);
      await _localDataSource.clearAllData();
      await _encryptionService.clearKey();
      final secureStorage = sl<FlutterSecureStorage>();
      await secureStorage.delete(key: 'last_sync_timestamp_$uid');
      await _firebaseAuth.signOut();
      return const Success(null);
    } catch (e) {
      return FailureResult(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> syncWithCloud() async {
    if (syncEngineTrigger != null) {
      return await syncEngineTrigger!();
    }
    return const Success(null);
  }

  Future<bool> _isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  @override
  Future<Result<void>> renameFolder(String oldName, String newName) async {
    try {
      await _localDataSource.renameFolder(_currentUserId, oldName, newName);
      _triggerSyncAsynchronously();
      return const Success(null);
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteFolder(String folderName, {required bool deleteNotes}) async {
    try {
      await _localDataSource.deleteFolder(_currentUserId, folderName, deleteNotes);
      _triggerSyncAsynchronously();
      return const Success(null);
    } catch (e) {
      return FailureResult(DatabaseFailure(e.toString()));
    }
  }

  void _triggerSyncAsynchronously() {
    _isConnected().then((connected) {
      if (connected) {
        syncWithCloud();
      }
    });
  }
}
