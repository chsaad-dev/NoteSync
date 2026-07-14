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

  List<IsarNoteModel> _getWebNotesList(String ownerId, bool isDeleted) {
    final list = _webNotes.values
        .where((n) => n.ownerId == ownerId && n.isDeleted == isDeleted)
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
}
