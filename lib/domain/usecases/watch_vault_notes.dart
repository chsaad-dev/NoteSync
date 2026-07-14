import '../entities/note_entity.dart';
import '../repository/note_repository.dart';

class WatchVaultNotes {
  final NoteRepository _repository;
  WatchVaultNotes(this._repository);

  Stream<List<NoteEntity>> call() {
    return _repository.watchVault();
  }
}
