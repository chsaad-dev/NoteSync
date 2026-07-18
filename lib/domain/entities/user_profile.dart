class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int usedStorage;
  final int maxStorage;

  const UserProfile({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.photoUrl,
    required this.usedStorage,
    required this.maxStorage,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    return UserProfile(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      usedStorage: map['usedStorage'] as int? ?? 0,
      maxStorage: map['maxStorage'] as int? ?? 314572800, // Default 300MB in bytes
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'usedStorage': usedStorage,
      'maxStorage': maxStorage,
    };
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    int? usedStorage,
    int? maxStorage,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      usedStorage: usedStorage ?? this.usedStorage,
      maxStorage: maxStorage ?? this.maxStorage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl &&
          usedStorage == other.usedStorage &&
          maxStorage == other.maxStorage;

  @override
  int get hashCode =>
      uid.hashCode ^
      email.hashCode ^
      displayName.hashCode ^
      photoUrl.hashCode ^
      usedStorage.hashCode ^
      maxStorage.hashCode;
}
