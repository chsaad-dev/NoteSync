import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user_profile.dart';
import 'auth_provider.dart';

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is Authenticated) {
    final uid = authState.user.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            final email = authState.user.email ?? '';
            final fallbackName = email.split('@').first;
            return UserProfile(
              uid: uid,
              email: email,
              displayName: fallbackName.isNotEmpty ? fallbackName : 'User',
              usedStorage: 0,
              maxStorage: 314572800, // Default 300MB
            );
          }
          return UserProfile.fromMap(snapshot.data()!, uid);
        });
  }
  return Stream.value(null);
});
