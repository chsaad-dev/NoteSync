import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class RenameFolder {
  final NoteRepository _repository;
  RenameFolder(this._repository);

  Future<Result<void>> call(String oldName, String newName) {
    return _repository.renameFolder(oldName, newName);
  }
}
