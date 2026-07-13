import '../../core/errors/result.dart';
import '../entities/note_entity.dart';
import '../repository/note_repository.dart';

class CreateNote {
  final NoteRepository _repository;
  CreateNote(this._repository);

  Future<Result<void>> call(NoteEntity note) {
    return _repository.saveNote(note);
  }
}
