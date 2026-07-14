import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/di/injection_container.dart';

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
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        state = Authenticated(user);
      } else {
        state = const Unauthenticated();
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
        // link the Google credential to the existing account so the
        // same UID (and therefore the same notes) are used.
        if (e.code == 'account-exists-with-different-credential') {
          final email = googleUser.email;
          final methods = await _auth.fetchSignInMethodsForEmail(email);
          if (methods.contains('password')) {
            // The user has an existing email/password account.
            // We can't auto-link without their password, so sign in with
            // the Google credential anyway (Firebase may auto-merge if
            // "One account per email" is enabled). If not, inform the user.
            state = AuthError(
              'An account already exists with $email. '
              'Please sign in with your email & password first, then link Google from Settings.',
            );
            return;
          }
          // For other providers, attempt to sign in directly
          await _auth.signInWithCredential(credential);
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
