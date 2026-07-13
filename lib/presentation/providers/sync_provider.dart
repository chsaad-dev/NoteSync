import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../core/di/injection_container.dart';
import '../../domain/repository/note_repository.dart';

class SyncState {
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final String? error;

  SyncState({
    this.isSyncing = false,
    this.lastSyncTime,
    this.error,
  });

  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    String? error,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      error: error ?? this.error,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final NoteRepository _repository;
  final FlutterSecureStorage _secureStorage;
  final fb.FirebaseAuth _firebaseAuth;

  SyncNotifier(this._repository, this._secureStorage, this._firebaseAuth) : super(SyncState()) {
    _loadLastSyncTime();
    // Listen to auth changes to reload sync time for different users
    _firebaseAuth.authStateChanges().listen((user) {
      if (user != null) {
        _loadLastSyncTime();
      } else {
        state = SyncState();
      }
    });
  }

  String get _syncTimeKey {
    final uid = _firebaseAuth.currentUser?.uid ?? '';
    return 'last_sync_timestamp_$uid';
  }

  Future<void> _loadLastSyncTime() async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    
    final timestamp = await _secureStorage.read(key: _syncTimeKey);
    if (timestamp != null) {
      state = state.copyWith(lastSyncTime: DateTime.parse(timestamp));
    }
  }

  Future<void> syncNow() async {
    if (state.isSyncing) return;
    
    state = state.copyWith(isSyncing: true, error: null);
    
    final result = await _repository.syncWithCloud();
    await result.fold(
      (success) async {
        final now = DateTime.now();
        // The SyncEngine updates the sync timestamp on secure storage, but we can reload it here:
        await _loadLastSyncTime();
        // If lastSyncTime was not updated by SyncEngine (e.g. no updates needed), we set it to now
        if (state.lastSyncTime == null || now.difference(state.lastSyncTime!).inMinutes > 2) {
          state = state.copyWith(isSyncing: false, lastSyncTime: now);
        } else {
          state = state.copyWith(isSyncing: false);
        }
      },
      (failure) async {
        state = state.copyWith(isSyncing: false, error: failure.message);
      },
    );
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    sl<NoteRepository>(),
    sl<FlutterSecureStorage>(),
    sl<fb.FirebaseAuth>(),
  );
});
