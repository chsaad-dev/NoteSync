class NoteEntity {
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
  final bool isPublic;
  final String? publicUrlId;

  const NoteEntity({
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
    this.isPublic = false,
    this.publicUrlId,
  });

  NoteEntity copyWith({
    String? noteId,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    bool? isDeleted,
    bool? isSynced,
    List<String>? tags,
    String? folderId,
    List<String>? mediaUrls,
    String? ownerId,
    bool? isVault,
    DateTime? reminderAt,
    bool clearReminder = false,
    bool? isPublic,
    String? publicUrlId,
    bool clearPublicUrlId = false,
  }) {
    return NoteEntity(
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      ownerId: ownerId ?? this.ownerId,
      isVault: isVault ?? this.isVault,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      isPublic: isPublic ?? this.isPublic,
      publicUrlId: clearPublicUrlId ? null : (publicUrlId ?? this.publicUrlId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteEntity &&
          runtimeType == other.runtimeType &&
          noteId == other.noteId &&
          title == other.title &&
          body == other.body &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          isPinned == other.isPinned &&
          isDeleted == other.isDeleted &&
          isSynced == other.isSynced &&
          tags == other.tags &&
          folderId == other.folderId &&
          mediaUrls == other.mediaUrls &&
          ownerId == other.ownerId &&
          isVault == other.isVault &&
          reminderAt == other.reminderAt &&
          isPublic == other.isPublic &&
          publicUrlId == other.publicUrlId;

  @override
  int get hashCode =>
      noteId.hashCode ^
      title.hashCode ^
      body.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      isPinned.hashCode ^
      isDeleted.hashCode ^
      isSynced.hashCode ^
      tags.hashCode ^
      folderId.hashCode ^
      mediaUrls.hashCode ^
      ownerId.hashCode ^
      isVault.hashCode ^
      reminderAt.hashCode ^
      isPublic.hashCode ^
      publicUrlId.hashCode;
}
