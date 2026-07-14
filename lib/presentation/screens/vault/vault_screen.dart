import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/quill_helper.dart';
import '../../../domain/entities/note_entity.dart';
import '../../providers/notes_provider.dart';
import '../note_editor/note_editor_screen.dart';

class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultNotesAsync = ref.watch(vaultStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.amber),
            SizedBox(width: 8),
            Text('Private Vault'),
          ],
        ),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0A0A0A),
      body: vaultNotesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_person_outlined, size: 80, color: Colors.grey.shade700),
                  const SizedBox(height: 16),
                  const Text(
                    'Your Private Vault is Empty',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lock sensitive notes from the editor menu to secure them here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
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
              return _buildVaultNoteCard(context, notes[index]);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Error loading vault: $e', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildVaultNoteCard(BuildContext context, NoteEntity note) {
    final plainBody = QuillHelper.toPlainText(note.body);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: Colors.grey.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade800, width: 1),
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: note.title.isEmpty ? Colors.grey : Colors.white,
                      ),
                    ),
                  ),
                  const Icon(Icons.lock, size: 14, color: Colors.amber),
                ],
              ),
              const SizedBox(height: 6),
              // Body Preview
              Expanded(
                child: Text(
                  plainBody.isEmpty ? 'No additional text' : plainBody,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: plainBody.isEmpty ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Folder Indicator
              if (note.folderId != null && note.folderId!.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.folder, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        note.folderId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
