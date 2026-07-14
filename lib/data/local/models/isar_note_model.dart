import 'package:isar/isar.dart';
import '../../../domain/entities/note_entity.dart';

part 'isar_note_model.g.dart';

@collection
class IsarNoteModel {
  Id? id; // Auto-incrementing local ID

  @Index(unique: true, replace: true)
  late String noteId;

  late String title;
  late String encryptedBody;
  late String iv;

  late DateTime createdAt;
  late DateTime updatedAt;

  late bool isPinned;
  late bool isDeleted;
  late bool isSynced;
  late bool isVault;

  late List<String> tags;
  String? folderId;
  late List<String> mediaUrls;
  late String ownerId;

  IsarNoteModel();

  factory IsarNoteModel.fromEntity({
    required NoteEntity entity,
    required String encryptedBody,
    required String iv,
  }) {
    return IsarNoteModel()
      ..noteId = entity.noteId
      ..title = entity.title
      ..encryptedBody = encryptedBody
      ..iv = iv
      ..createdAt = entity.createdAt
      ..updatedAt = entity.updatedAt
      ..isPinned = entity.isPinned
      ..isDeleted = entity.isDeleted
      ..isSynced = entity.isSynced
      ..isVault = entity.isVault
      ..tags = entity.tags
      ..folderId = entity.folderId
      ..mediaUrls = entity.mediaUrls
      ..ownerId = entity.ownerId;
  }

  NoteEntity toEntity(String decryptedBody) {
    return NoteEntity(
      noteId: noteId,
      title: title,
      body: decryptedBody,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPinned: isPinned,
      isDeleted: isDeleted,
      isSynced: isSynced,
      tags: tags,
      folderId: folderId,
      mediaUrls: mediaUrls,
      ownerId: ownerId,
      isVault: isVault,
    );
  }
}
