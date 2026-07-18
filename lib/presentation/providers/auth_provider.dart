import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:isar/isar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/di/injection_container.dart';
import '../../core/security/session_manager.dart';
import '../../core/security/encryption_service.dart';
import '../../data/sync/sync_engine.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Authenticated extends AuthState {
  final fb.User user;
  const Authenticated(this.user);
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '608360411758-8j75tt0990rdjuudlc1cgq0e6p8mo075.apps.googleusercontent.com' : null,
  );

  AuthNotifier(this._auth) : super(const AuthInitial()) {
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        state = Authenticated(user);
        await SessionManager.updateSession(user.uid);
        await SessionManager.setupRevocationListener(user.uid, () async {
          await SessionManager.performLocalWipeAndLogout();
        });
      } else {
        state = const Unauthenticated();
        await SessionManager.cancelRevocationListener();
      }
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AuthLoading();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on fb.FirebaseAuthException catch (e) {
      state = AuthError(e.message ?? 'Authentication failed');
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = const AuthLoading();
    try {
      final credentials = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await credentials.user?.sendEmailVerification();
    } on fb.FirebaseAuthException catch (e) {
      state = AuthError(e.message ?? 'Registration failed');
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> sendForgotPasswordEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb.FirebaseAuthException catch (e) {
      state = AuthError(e.message ?? 'Password reset failed');
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AuthLoading();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        state = const Unauthenticated();
        return;
      }
      final googleAuth = await googleUser.authentication;
      final fb.OAuthCredential credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      try {
        await _auth.signInWithCredential(credential);
      } on fb.FirebaseAuthException catch (e) {
        // If an email/password account already exists with this email,
        // Firebase can't auto-link without the user's password.
        if (e.code == 'account-exists-with-different-credential') {
          final email = googleUser.email;
          state = AuthError(
            'An account already exists with $email. '
            'Please sign in with your email & password first, then link Google from Settings.',
          );
          return;
        } else {
          rethrow;
        }
      }
    } on fb.FirebaseAuthException catch (e) {
      state = AuthError(e.message ?? 'Google Sign-In failed');
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signOut() async {
    state = const AuthLoading();
    try {
      // 1. Cancel in-flight sync operation immediately
      if (sl.isRegistered<SyncEngine>()) {
        sl<SyncEngine>().cancelSync();
      }

      // 2. Perform local wipe BEFORE Firebase sign out to capture current UID
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // Cancel revocation listener
        await SessionManager.cancelRevocationListener();

        // Wipe local Isar database notes
        if (sl.isRegistered<Isar>()) {
          final isar = sl<Isar>();
          await isar.writeTxn(() async {
            await isar.clear();
          });
        }

        // Clear secure storage keys
        final secureStorage = sl<FlutterSecureStorage>();
        await secureStorage.delete(key: 'notesync_aes_key');
        await secureStorage.delete(key: 'last_sync_timestamp_$uid');

        // Clear cached key in EncryptionService
        if (sl.isRegistered<EncryptionService>()) {
          await sl<EncryptionService>().clearKey();
        }
      }

      await _googleSignIn.signOut();
      await _auth.signOut();
      state = const Unauthenticated();
    } catch (e) {
      state = AuthError(e.toString());
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(sl<fb.FirebaseAuth>());
});

final userIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is Authenticated) {
    return authState.user.uid;
  }
  return null;
});
