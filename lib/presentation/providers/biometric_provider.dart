import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/di/injection_container.dart';

class BiometricState {
  final bool isEnabled;
  final bool isLocked;
  final String? error;

  BiometricState({
    this.isEnabled = false,
    this.isLocked = false,
    this.error,
  });

  BiometricState copyWith({
    bool? isEnabled,
    bool? isLocked,
    String? error,
  }) {
    return BiometricState(
      isEnabled: isEnabled ?? this.isEnabled,
      isLocked: isLocked ?? this.isLocked,
      error: error ?? this.error,
    );
  }
}

class BiometricNotifier extends StateNotifier<BiometricState> {
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _auth = LocalAuthentication();
  static const _biometricKey = 'notesync_biometric_enabled';

  BiometricNotifier(this._secureStorage) : super(BiometricState()) {
    _loadBiometricStatus();
  }

  Future<void> _loadBiometricStatus() async {
    final enabledStr = await _secureStorage.read(key: _biometricKey);
    final isEnabled = enabledStr == 'true';
    state = BiometricState(isEnabled: isEnabled, isLocked: isEnabled);
  }

  Future<void> toggleBiometric(bool enable) async {
    try {
      final canAuthenticate = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuthenticate && enable) {
        state = state.copyWith(error: 'Biometrics not available on this device');
        return;
      }

      if (enable) {
        final success = await authenticate();
        if (success) {
          await _secureStorage.write(key: _biometricKey, value: 'true');
          state = BiometricState(isEnabled: true, isLocked: false);
        } else {
          state = state.copyWith(error: 'Authentication failed. Could not enable lock.');
        }
      } else {
        await _secureStorage.write(key: _biometricKey, value: 'false');
        state = BiometricState(isEnabled: false, isLocked: false);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> authenticate() async {
    try {
      final success = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock NoteSync',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (success) {
        state = state.copyWith(isLocked: false);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void lock() {
    if (state.isEnabled) {
      state = state.copyWith(isLocked: true);
    }
  }

  void unlock() {
    state = state.copyWith(isLocked: false);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final biometricProvider = StateNotifierProvider<BiometricNotifier, BiometricState>((ref) {
  return BiometricNotifier(sl<FlutterSecureStorage>());
});
