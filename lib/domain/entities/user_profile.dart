class UserProfile {
  final String uid;
  final String email;
  final int usedStorage;
  final int maxStorage;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.usedStorage,
    required this.maxStorage,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    return UserProfile(
      uid: uid,
      email: map['email'] as String? ?? '',
      usedStorage: map['usedStorage'] as int? ?? 0,
      maxStorage: map['maxStorage'] as int? ?? 314572800, // Default 300MB in bytes
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'usedStorage': usedStorage,
      'maxStorage': maxStorage,
    };
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    int? usedStorage,
    int? maxStorage,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
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
          usedStorage == other.usedStorage &&
          maxStorage == other.maxStorage;

  @override
  int get hashCode =>
      uid.hashCode ^ email.hashCode ^ usedStorage.hashCode ^ maxStorage.hashCode;
}
