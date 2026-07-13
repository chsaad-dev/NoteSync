import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class DeleteAccount {
  final NoteRepository _repository;
  DeleteAccount(this._repository);

  Future<Result<void>> call() {
    return _repository.deleteAccount();
  }
}
