import '../../core/errors/result.dart';
import '../entities/note_entity.dart';

abstract class NoteRepository {
  Stream<List<NoteEntity>> watchNotes();
  Stream<List<NoteEntity>> watchTrash();
  Future<Result<List<NoteEntity>>> getNotes();
  Future<Result<NoteEntity?>> getNoteById(String noteId);
  Future<Result<void>> saveNote(NoteEntity note);
  Future<Result<void>> deleteNote(String noteId, {bool permanent = false});
  Future<Result<void>> syncWithCloud();
  Future<Result<void>> deleteAccount();
  Future<Result<String>> uploadMedia(String filePath);
  Future<Result<void>> deleteMedia(String mediaUrl);
}
