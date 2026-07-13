import '../../core/errors/result.dart';
import '../repository/note_repository.dart';

class UploadMedia {
  final NoteRepository _repository;
  UploadMedia(this._repository);

  Future<Result<String>> call(String filePath) {
    return _repository.uploadMedia(filePath);
  }
}
