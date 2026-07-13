import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class DeleteNote {
  final NoteRepository _repository;
  DeleteNote(this._repository);

  Future<Result<void>> call(String noteId, {bool permanent = false}) {
    return _repository.deleteNote(noteId, permanent: permanent);
  }
}
