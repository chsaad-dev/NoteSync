import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/note_entity.dart';

class FirestoreNoteModel {
  final String noteId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isDeleted;
  final bool isSynced;
  final List<String> tags;
  final String? folderId;
  final List<String> mediaUrls;
  final String ownerId;
  final bool isVault;
  final DateTime? reminderAt;

  FirestoreNoteModel({
    required this.noteId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.isPinned,
    required this.isDeleted,
    required this.isSynced,
    required this.tags,
    this.folderId,
    required this.mediaUrls,
    required this.ownerId,
    this.isVault = false,
    this.reminderAt,
  });

  factory FirestoreNoteModel.fromEntity(NoteEntity entity) {
    return FirestoreNoteModel(
      noteId: entity.noteId,
      title: entity.title,
      body: entity.body,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      isPinned: entity.isPinned,
      isDeleted: entity.isDeleted,
      isSynced: entity.isSynced,
      tags: entity.tags,
      folderId: entity.folderId,
      mediaUrls: entity.mediaUrls,
      ownerId: entity.ownerId,
      isVault: entity.isVault,
      reminderAt: entity.reminderAt,
    );
  }

  NoteEntity toEntity() {
    return NoteEntity(
      noteId: noteId,
      title: title,
      body: body,
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
      reminderAt: reminderAt,
    );
  }

  factory FirestoreNoteModel.fromJson(Map<String, dynamic> json, String docId) {
    return FirestoreNoteModel(
      noteId: docId,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPinned: json['isPinned'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      isSynced: true,
      tags: List<String>.from(json['tags'] ?? []),
      folderId: json['folderId'] as String?,
      mediaUrls: List<String>.from(json['mediaUrls'] ?? []),
      ownerId: json['ownerId'] as String? ?? '',
      isVault: json['isVault'] as bool? ?? false,
      reminderAt: (json['reminderAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'title': title,
      'body': body,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isPinned': isPinned,
      'isDeleted': isDeleted,
      'tags': tags,
      'folderId': folderId,
      'mediaUrls': mediaUrls,
      'isVault': isVault,
      'reminderAt': reminderAt != null ? Timestamp.fromDate(reminderAt!) : null,
    };
  }
}
