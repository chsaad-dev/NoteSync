import '../../core/errors/result.dart';
import '../entities/note_entity.dart';
import '../repository/note_repository.dart';

class UpdateNote {
  final NoteRepository _repository;
  UpdateNote(this._repository);

  Future<Result<void>> call(NoteEntity note) {
    return _repository.saveNote(note);
  }
}
