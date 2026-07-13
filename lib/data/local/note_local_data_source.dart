import 'package:isar/isar.dart';
import 'models/isar_note_model.dart';

class NoteLocalDataSource {
  final Isar _isar;

  NoteLocalDataSource(this._isar);

  Stream<List<IsarNoteModel>> watchNotes(String ownerId) {
    return _isar.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(false)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<IsarNoteModel>> watchTrash(String ownerId) {
    return _isar.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(true)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<IsarNoteModel>> getNotes(String ownerId) async {
    return await _isar.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .findAll();
  }

  Future<IsarNoteModel?> getNoteById(String noteId) async {
    return await _isar.isarNoteModels
        .filter()
        .noteIdEqualTo(noteId)
        .findFirst();
  }

  Future<void> saveNote(IsarNoteModel model) async {
    await _isar.writeTxn(() async {
      // Find existing by noteId to preserve local auto-increment id
      final existing = await getNoteById(model.noteId);
      if (existing != null) {
        model.id = existing.id;
      }
      await _isar.isarNoteModels.put(model);
    });
  }

  Future<void> saveNotes(List<IsarNoteModel> models) async {
    await _isar.writeTxn(() async {
      for (var model in models) {
        final existing = await getNoteById(model.noteId);
        if (existing != null) {
          model.id = existing.id;
        }
      }
      await _isar.isarNoteModels.putAll(models);
    });
  }

  Future<void> deleteNote(String noteId) async {
    await _isar.writeTxn(() async {
      final existing = await getNoteById(noteId);
      if (existing != null) {
        await _isar.isarNoteModels.delete(existing.id!);
      }
    });
  }

  Future<List<IsarNoteModel>> getUnsyncedNotes(String ownerId) async {
    return await _isar.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isSyncedEqualTo(false)
        .findAll();
  }

  Future<List<IsarNoteModel>> getDeletedNotesOlderThan(String ownerId, DateTime cutOff) async {
    return await _isar.isarNoteModels
        .filter()
        .ownerIdEqualTo(ownerId)
        .isDeletedEqualTo(true)
        .updatedAtLessThan(cutOff)
        .findAll();
  }

  Future<void> hardDeleteNotes(List<String> noteIds) async {
    await _isar.writeTxn(() async {
      for (final noteId in noteIds) {
        final existing = await getNoteById(noteId);
        if (existing != null) {
          await _isar.isarNoteModels.delete(existing.id!);
        }
      }
    });
  }

  Future<void> clearAllData() async {
    await _isar.writeTxn(() async {
      await _isar.isarNoteModels.clear();
    });
  }
}
