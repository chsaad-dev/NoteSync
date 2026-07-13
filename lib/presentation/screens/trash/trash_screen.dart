import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/quill_helper.dart';
import '../../domain/entities/note_entity.dart';
import '../../providers/notes_provider.dart';
import '../../providers/editor_provider.dart';
import '../note_editor/note_editor_screen.dart';
import '../../core/di/injection_container.dart';
import '../../domain/repository/note_repository.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  void _restoreNote(BuildContext context, WidgetRef ref, NoteEntity note) async {
    final restoredNote = note.copyWith(
      isDeleted: false,
      isSynced: false,
      updatedAt: DateTime.now(),
    );
    final repo = sl<NoteRepository>();
    final result = await repo.saveNote(restoredNote);
    
    result.fold(
      (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note restored'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: ${failure.message}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _confirmPermanentDelete(BuildContext context, WidgetRef ref, NoteEntity note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Permanently?'),
        content: const Text(
          'This action cannot be undone. All text contents and attached Cloudinary media will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              
              final repo = sl<NoteRepository>();
              final result = await repo.deleteNote(note.noteId, permanent: true);
              
              result.fold(
                (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Note permanently deleted'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                (failure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Delete failed: ${failure.message}'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashNotesAsync = ref.watch(trashStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
      ),
      body: SafeArea(
        child: trashNotesAsync.when(
          data: (notes) {
            if (notes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Trash is empty',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final plainBody = QuillHelper.toPlainText(note.body);
                
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: note.title.isEmpty ? Colors.grey : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            plainBody.isEmpty ? 'No text' : plainBody,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: plainBody.isEmpty ? Colors.grey.shade500 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, size: 20, color: Colors.green),
                              tooltip: 'Restore Note',
                              onPressed: () => _restoreNote(context, ref, note),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
                              tooltip: 'Delete Permanently',
                              onPressed: () => _confirmPermanentDelete(context, ref, note),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error loading trash: $err')),
        ),
      ),
    );
  }
}
