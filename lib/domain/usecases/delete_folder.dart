import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class DeleteFolder {
  final NoteRepository _repository;
  DeleteFolder(this._repository);

  Future<Result<void>> call(String folderName, {required bool deleteNotes}) {
    return _repository.deleteFolder(folderName, deleteNotes: deleteNotes);
  }
}
