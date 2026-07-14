import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/injection_container.dart';
import '../../../domain/usecases/rename_folder.dart';
import '../../../domain/usecases/delete_folder.dart';
import '../../providers/notes_provider.dart';

class FoldersManagerScreen extends ConsumerWidget {
  const FoldersManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allFolders = ref.watch(allFoldersProvider);
    final notesAsync = ref.watch(notesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Folders'),
      ),
      body: notesAsync.when(
        data: (notes) {
          if (allFolders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No folders found',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Folders are created when you categorize notes',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          // Count active notes in each folder
          final folderCounts = <String, int>{};
          for (final folder in allFolders) {
            folderCounts[folder] = notes.where((n) => n.folderId == folder).length;
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: allFolders.length,
            itemBuilder: (context, index) {
              final folder = allFolders[index];
              final count = folderCounts[folder] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.folder,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    folder,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '$count ${count == 1 ? "note" : "notes"}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                        onPressed: () => _renameFolderDialog(context, ref, folder),
                        tooltip: 'Rename Folder',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteFolderDialog(context, ref, folder, count),
                        tooltip: 'Delete Folder',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Error loading folders: $e')),
      ),
    );
  }

  void _renameFolderDialog(BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'New folder name',
            labelText: 'Folder Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == currentName) {
                Navigator.pop(dialogContext);
                return;
              }

              Navigator.pop(dialogContext);
              final renameFolderUseCase = sl<RenameFolder>();
              final result = await renameFolderUseCase(currentName, newName);

              if (context.mounted) {
                result.fold(
                  (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Folder renamed to "$newName"'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  (failure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rename failed: ${failure.message}'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteFolderDialog(BuildContext context, WidgetRef ref, String folderName, int count) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Folder "$folderName"?'),
        content: Text(
          'This folder contains $count ${count == 1 ? "note" : "notes"}.\n\n'
          'What would you like to do with the notes?',
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final deleteFolderUseCase = sl<DeleteFolder>();
                  final result = await deleteFolderUseCase(folderName, deleteNotes: false);

                  if (context.mounted) {
                    result.fold(
                      (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Folder deleted. Notes moved to uncategorized.'),
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
                  }
                },
                child: const Text('Keep Notes (Uncategorize)', style: TextStyle(color: Colors.blue)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final deleteFolderUseCase = sl<DeleteFolder>();
                  final result = await deleteFolderUseCase(folderName, deleteNotes: true);

                  if (context.mounted) {
                    result.fold(
                      (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Folder and notes moved to Trash'),
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
                  }
                },
                child: const Text('Delete Folder & Notes', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
