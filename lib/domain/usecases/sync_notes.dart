import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class SyncNotes {
  final NoteRepository _repository;
  SyncNotes(this._repository);

  Future<Result<void>> call() {
    return _repository.syncWithCloud();
  }
}
