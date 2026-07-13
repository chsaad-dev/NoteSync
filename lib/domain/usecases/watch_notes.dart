import '../entities/note_entity.dart';
import '../repository/note_repository.dart';

class WatchNotes {
  final NoteRepository _repository;
  WatchNotes(this._repository);

  Stream<List<NoteEntity>> call() {
    return _repository.watchNotes();
  }
}
