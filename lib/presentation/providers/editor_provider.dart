import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../core/di/injection_container.dart';
import '../../domain/entities/note_entity.dart';
import '../../domain/repository/note_repository.dart';
import '../../core/notifications/notification_manager.dart';
import '../../core/utils/quill_helper.dart';
import 'auth_provider.dart';


class NoteEditorState {
  final NoteEntity? note;
  final bool isSaving;
  final bool isUploadingMedia;
  final double uploadProgress;
  final String? error;

  NoteEditorState({
    this.note,
    this.isSaving = false,
    this.isUploadingMedia = false,
    this.uploadProgress = 0.0,
    this.error,
  });

  NoteEditorState copyWith({
    NoteEntity? note,
    bool? isSaving,
    bool? isUploadingMedia,
    double? uploadProgress,
    String? error,
  }) {
    return NoteEditorState(
      note: note ?? this.note,
      isSaving: isSaving ?? this.isSaving,
      isUploadingMedia: isUploadingMedia ?? this.isUploadingMedia,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error ?? this.error,
    );
  }
}

class NoteEditorNotifier extends StateNotifier<NoteEditorState> {
  final NoteRepository _repository;
  final Ref _ref;
  Timer? _debounceTimer;

  NoteEditorNotifier(this._repository, this._ref) : super(NoteEditorState());

  void initNote(NoteEntity? existingNote) {
    if (existingNote != null) {
      if (existingNote.reminderAt != null && existingNote.reminderAt!.isBefore(DateTime.now())) {
        final cleared = existingNote.copyWith(clearReminder: true);
        state = NoteEditorState(note: cleared);
        _repository.saveNote(cleared);
      } else {
        state = NoteEditorState(note: existingNote);
      }
    } else {
      final userState = _ref.read(authProvider);
      String ownerId = '';
      if (userState is Authenticated) {
        ownerId = userState.user.uid;
      }
      state = NoteEditorState(
        note: NoteEntity(
          noteId: const Uuid().v4(),
          title: '',
          body: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isPinned: false,
          isDeleted: false,
          isSynced: false,
          tags: [],
          mediaUrls: [],
          ownerId: ownerId,
        ),
      );
    }
  }

  void updateNoteContent({
    String? title,
    String? body,
    List<String>? tags,
    String? folderId,
    bool? isPinned,
    bool? isVault,
    DateTime? reminderAt,
    bool clearReminder = false,
  }) {
    final currentNote = state.note;
    if (currentNote == null) return;

    final updated = currentNote.copyWith(
      title: title ?? currentNote.title,
      body: body ?? currentNote.body,
      tags: tags ?? currentNote.tags,
      folderId: folderId ?? currentNote.folderId,
      isPinned: isPinned ?? currentNote.isPinned,
      isVault: isVault ?? currentNote.isVault,
      reminderAt: reminderAt,
      clearReminder: clearReminder,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    state = state.copyWith(note: updated);

    // Debounced autosave (500ms)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      save();
    });
  }

  Future<void> save() async {
    final currentNote = state.note;
    if (currentNote == null) return;

    // Enforce specifications validation
    if (currentNote.title.length > 200) {
      state = state.copyWith(error: 'Title cannot exceed 200 characters');
      return;
    }
    if (currentNote.body.length > 100000) {
      state = state.copyWith(error: 'Note body cannot exceed 100k characters');
      return;
    }

    state = state.copyWith(isSaving: true, error: null);
    final result = await _repository.saveNote(currentNote);
    result.fold(
      (success) {
        state = state.copyWith(isSaving: false);

        // Schedule or cancel notification reminder
        final notificationId = currentNote.noteId.hashCode & 0x7FFFFFFF;
        if (currentNote.reminderAt != null && currentNote.reminderAt!.isAfter(DateTime.now())) {
          String previewText = 'Tap to open note';
          if (currentNote.body.isNotEmpty) {
            try {
              final text = QuillHelper.toPlainText(currentNote.body);
              if (text.trim().isNotEmpty) {
                previewText = text.length > 50 ? '${text.substring(0, 50)}...' : text;
              }
            } catch (_) {}
          }
          NotificationManager.scheduleNotification(
            id: notificationId,
            title: currentNote.title.isNotEmpty ? currentNote.title : 'Reminder',
            body: previewText,
            scheduledDate: currentNote.reminderAt!,
            payload: currentNote.noteId,
          );
        } else {
          NotificationManager.cancelNotification(notificationId);
        }
      },
      (failure) {
        state = state.copyWith(isSaving: false, error: failure.message);
      },
    );
  }

  Future<void> attachMedia(String filePath) async {
    final currentNote = state.note;
    if (currentNote == null) return;

    state = state.copyWith(isUploadingMedia: true, uploadProgress: 0.1, error: null);
    
    // Smooth progress simulation
    Timer? progressTimer;
    progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (state.uploadProgress < 0.9 && state.isUploadingMedia) {
        state = state.copyWith(uploadProgress: state.uploadProgress + 0.05);
      } else {
        timer.cancel();
      }
    });

    final uploadResult = await _repository.uploadMedia(filePath);
    progressTimer.cancel();

    await uploadResult.fold(
      (url) async {
        final updatedUrls = List<String>.from(currentNote.mediaUrls)..add(url);
        final updatedNote = currentNote.copyWith(
          mediaUrls: updatedUrls,
          updatedAt: DateTime.now(),
          isSynced: false,
        );
        state = state.copyWith(
          note: updatedNote,
          isUploadingMedia: false,
          uploadProgress: 1.0,
        );
        await save();
      },
      (failure) async {
        state = state.copyWith(
          isUploadingMedia: false,
          uploadProgress: 0.0,
          error: 'Failed to upload media: ${failure.message}',
        );
      },
    );
  }

  Future<void> removeMedia(String url) async {
    final currentNote = state.note;
    if (currentNote == null) return;

    final updatedUrls = List<String>.from(currentNote.mediaUrls)..remove(url);
    final updatedNote = currentNote.copyWith(
      mediaUrls: updatedUrls,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    state = state.copyWith(note: updatedNote);
    await save();

    // Call deleteMedia in background (fails silently if offline, will be cleaned up in worker later)
    await _repository.deleteMedia(url);
  }

  Future<void> publishNote() async {
    final currentNote = state.note;
    if (currentNote == null) return;

    state = state.copyWith(isSaving: true, error: null);

    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final idToken = await user.getIdToken();

      final publicUrlId = const Uuid().v4();
      final contentHtml = QuillHelper.toHtml(currentNote.body);

      final rawWorkerUrl = dotenv.env['CLOUDFLARE_WORKER_URL'] ?? 'https://your-worker-url.workers.dev';
      final workerUrl = rawWorkerUrl.endsWith('/') 
          ? rawWorkerUrl.substring(0, rawWorkerUrl.length - 1) 
          : rawWorkerUrl;
      final response = await http.post(
        Uri.parse('$workerUrl/publish-note'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'noteId': currentNote.noteId,
          'publicUrlId': publicUrlId,
          'title': currentNote.title.isNotEmpty ? currentNote.title : 'Untitled',
          'contentHtml': contentHtml,
          'mediaUrls': currentNote.mediaUrls,
          'createdAt': currentNote.createdAt.toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to publish note: ${response.body}');
      }

      // Update local state and save to sync
      final updated = currentNote.copyWith(
        isPublic: true,
        publicUrlId: publicUrlId,
        isSynced: false,
      );
      state = state.copyWith(note: updated, isSaving: false);
      await save();
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
    }
  }

  Future<void> unpublishNote() async {
    final currentNote = state.note;
    if (currentNote == null || currentNote.publicUrlId == null) return;

    state = state.copyWith(isSaving: true, error: null);

    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final idToken = await user.getIdToken();

      final rawWorkerUrl = dotenv.env['CLOUDFLARE_WORKER_URL'] ?? 'https://your-worker-url.workers.dev';
      final workerUrl = rawWorkerUrl.endsWith('/') 
          ? rawWorkerUrl.substring(0, rawWorkerUrl.length - 1) 
          : rawWorkerUrl;
      final response = await http.post(
        Uri.parse('$workerUrl/unpublish-note'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'noteId': currentNote.noteId,
          'publicUrlId': currentNote.publicUrlId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to unpublish note: ${response.body}');
      }

      // Update local state and save to sync
      final updated = currentNote.copyWith(
        isPublic: false,
        clearPublicUrlId: true,
        isSynced: false,
      );
      state = state.copyWith(note: updated, isSaving: false);
      await save();
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final noteEditorProvider = StateNotifierProvider<NoteEditorNotifier, NoteEditorState>((ref) {
  return NoteEditorNotifier(sl<NoteRepository>(), ref);
});
