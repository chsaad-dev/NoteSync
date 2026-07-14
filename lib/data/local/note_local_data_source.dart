import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'models/isar_note_model.dart';

class NoteLocalDataSource {
  final Isar? _isar;

  // Web / In-memory fallback database
  static final Map<String, IsarNoteModel> _webNotes = {};
  static final _streamController = StreamController<void>.broadcast();

  NoteLocalDataSource(this._isar);

  List<IsarNoteModel> _getWebNotesList(String ownerId, bool isDeleted, {bool isVault = false}) {
    final list = _webNotes.values
        .where((n) {
          if (isDeleted) {
            return n.ownerId == ownerId && n.isDeleted == true;
          } else {
            return n.ownerId == ownerId && n.isDeleted == false && n.isVault == isVault;
          }
        })
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Stream<List<IsarNoteModel>> watchNotes(String ownerId) {
    if (kIsWeb || _isar == null) {
      final controller = StreamController<List<IsarNoteModel>>();
      
      void emit() {
        if (!controller.isClosed) {
          controller.add(_getWebNotesList(ownerId, false));
        }
      }

      emit();
      final subscription = _streamController.stream.listen((_) => emit());
      controller.onCancel = () {
        subscription.cancel();
        controller.close();
      };
      
      return controller.stream;
    }

    return _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(false)
        .isVaultEqualTo(false)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<IsarNoteModel>> watchTrash(String ownerId) {
    if (kIsWeb || _isar == null) {
      final controller = StreamController<List<IsarNoteModel>>();
      
      void emit() {
        if (!controller.isClosed) {
          controller.add(_getWebNotesList(ownerId, true));
        }
      }

      emit();
      final subscription = _streamController.stream.listen((_) => emit());
      controller.onCancel = () {
        subscription.cancel();
        controller.close();
      };
      
      return controller.stream;
    }

    return _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(true)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<IsarNoteModel>> watchVault(String ownerId) {
    if (kIsWeb || _isar == null) {
      final controller = StreamController<List<IsarNoteModel>>();
      
      void emit() {
        if (!controller.isClosed) {
          controller.add(_getWebNotesList(ownerId, false, isVault: true));
        }
      }

      emit();
      final subscription = _streamController.stream.listen((_) => emit());
      controller.onCancel = () {
        subscription.cancel();
        controller.close();
      };
      
      return controller.stream;
    }

    return _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(false)
        .isVaultEqualTo(true)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<IsarNoteModel>> getNotes(String ownerId) async {
    if (kIsWeb || _isar == null) {
      return _webNotes.values.where((n) => n.ownerId == ownerId).toList();
    }
    return await _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .findAll();
  }

  Future<IsarNoteModel?> getNoteById(String noteId) async {
    if (kIsWeb || _isar == null) {
      return _webNotes[noteId];
    }
    return await _isar!.isarNoteModels
        .filter()
        .noteIdEqualTo(noteId)
        .findFirst();
  }

  Future<void> saveNote(IsarNoteModel model) async {
    if (kIsWeb || _isar == null) {
      if (model.id == null) {
        model.id = _webNotes.length + 1;
      }
      _webNotes[model.noteId] = model;
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      // Find existing by noteId to preserve local auto-increment id
      final existing = await getNoteById(model.noteId);
      if (existing != null) {
        model.id = existing.id;
      }
      await _isar!.isarNoteModels.put(model);
    });
  }

  Future<void> saveNotes(List<IsarNoteModel> models) async {
    if (kIsWeb || _isar == null) {
      for (var model in models) {
        if (model.id == null) {
          model.id = _webNotes.length + 1;
        }
        _webNotes[model.noteId] = model;
      }
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      for (var model in models) {
        final existing = await getNoteById(model.noteId);
        if (existing != null) {
          model.id = existing.id;
        }
      }
      await _isar!.isarNoteModels.putAll(models);
    });
  }

  Future<void> deleteNote(String noteId) async {
    if (kIsWeb || _isar == null) {
      _webNotes.remove(noteId);
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      final existing = await getNoteById(noteId);
      if (existing != null) {
        await _isar!.isarNoteModels.delete(existing.id!);
      }
    });
  }

  Future<List<IsarNoteModel>> getUnsyncedNotes(String ownerId) async {
    if (kIsWeb || _isar == null) {
      return _webNotes.values
          .where((n) => n.ownerId == ownerId && !n.isSynced)
          .toList();
    }
    return await _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isSyncedEqualTo(false)
        .findAll();
  }

  Future<List<IsarNoteModel>> getDeletedNotesOlderThan(String ownerId, DateTime cutOff) async {
    if (kIsWeb || _isar == null) {
      return _webNotes.values
          .where((n) => n.ownerId == ownerId && n.isDeleted && n.updatedAt.isBefore(cutOff))
          .toList();
    }
    return await _isar!.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(true)
        .updatedAtLessThan(cutOff)
        .findAll();
  }

  Future<void> hardDeleteNotes(List<String> noteIds) async {
    if (kIsWeb || _isar == null) {
      for (final noteId in noteIds) {
        _webNotes.remove(noteId);
      }
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      for (final noteId in noteIds) {
        final existing = await getNoteById(noteId);
        if (existing != null) {
          await _isar!.isarNoteModels.delete(existing.id!);
        }
      }
    });
  }

  Future<void> clearAllData() async {
    if (kIsWeb || _isar == null) {
      _webNotes.clear();
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      await _isar!.isarNoteModels.clear();
    });
  }

  Future<void> renameFolder(String ownerId, String oldName, String newName) async {
    if (kIsWeb || _isar == null) {
      for (final key in _webNotes.keys) {
        final model = _webNotes[key]!;
        if (model.ownerId == ownerId && model.folderId == oldName) {
          final updated = IsarNoteModel()
            ..id = model.id
            ..noteId = model.noteId
            ..title = model.title
            ..encryptedBody = model.encryptedBody
            ..iv = model.iv
            ..createdAt = model.createdAt
            ..updatedAt = DateTime.now()
            ..isPinned = model.isPinned
            ..isDeleted = model.isDeleted
            ..isSynced = false
            ..isVault = model.isVault
            ..tags = model.tags
            ..folderId = newName
            ..mediaUrls = model.mediaUrls
            ..ownerId = model.ownerId;
          _webNotes[key] = updated;
        }
      }
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      final matching = await _isar!.isarNoteModels
          .filter()
          .ownerIdEqualTo(ownerId)
          .folderIdEqualTo(oldName)
          .findAll();
      for (final model in matching) {
        model.folderId = newName;
        model.isSynced = false;
        model.updatedAt = DateTime.now();
      }
      await _isar!.isarNoteModels.putAll(matching);
    });
  }

  Future<void> deleteFolder(String ownerId, String folderName, bool deleteNotes) async {
    if (kIsWeb || _isar == null) {
      final keysToRemove = <String>[];
      for (final key in _webNotes.keys) {
        final model = _webNotes[key]!;
        if (model.ownerId == ownerId && model.folderId == folderName) {
          if (deleteNotes) {
            keysToRemove.add(key);
          } else {
            final updated = IsarNoteModel()
              ..id = model.id
              ..noteId = model.noteId
              ..title = model.title
              ..encryptedBody = model.encryptedBody
              ..iv = model.iv
              ..createdAt = model.createdAt
              ..updatedAt = DateTime.now()
              ..isPinned = model.isPinned
              ..isDeleted = model.isDeleted
              ..isSynced = false
              ..isVault = model.isVault
              ..tags = model.tags
              ..folderId = null
              ..mediaUrls = model.mediaUrls
              ..ownerId = model.ownerId;
            _webNotes[key] = updated;
          }
        }
      }
      for (final k in keysToRemove) {
        _webNotes.remove(k);
      }
      _streamController.add(null);
      return;
    }
    await _isar!.writeTxn(() async {
      final matching = await _isar!.isarNoteModels
          .filter()
          .ownerIdEqualTo(ownerId)
          .folderIdEqualTo(folderName)
          .findAll();
      if (deleteNotes) {
        for (final model in matching) {
          model.isDeleted = true;
          model.isSynced = false;
          model.updatedAt = DateTime.now();
        }
        await _isar!.isarNoteModels.putAll(matching);
      } else {
        for (final model in matching) {
          model.folderId = null;
          model.isSynced = false;
          model.updatedAt = DateTime.now();
        }
        await _isar!.isarNoteModels.putAll(matching);
      }
    });
  }
}
