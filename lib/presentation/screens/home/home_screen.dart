import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notesync/core/di/injection_container.dart';
import '../../../core/utils/quill_helper.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../domain/repository/note_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/sync_provider.dart';
import '../note_editor/note_editor_screen.dart';
import '../settings/settings_screen.dart';
import '../trash/trash_screen.dart';
import '../folders/folders_manager_screen.dart';
import '../vault/vault_screen.dart';
import '../../providers/biometric_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredNotes = ref.watch(filteredNotesProvider);
    final allTags = ref.watch(allTagsProvider);
    final allFolders = ref.watch(allFoldersProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final syncState = ref.watch(syncProvider);
    final authState = ref.watch(authProvider);

    // Group notes into pinned and unpinned
    final pinnedNotes = filteredNotes.where((note) => note.isPinned).toList();
    final unpinnedNotes = filteredNotes.where((note) => !note.isPinned).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteSync'),
        actions: [
          _buildSyncIndicator(context, ref, syncState),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: const Text('NoteSync User', style: TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(
                authState is Authenticated ? authState.user.email ?? '' : 'Offline Mode',
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary, size: 40),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('All Notes'),
              selected: selectedFolder == null,
              onTap: () {
                ref.read(selectedFolderProvider.notifier).state = null;
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Manage Folders'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const FoldersManagerScreen()));
              },
            ),
            if (allFolders.isNotEmpty) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text('Folders', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              ...allFolders.map((folder) => ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(folder),
                    selected: selectedFolder == folder,
                    onTap: () {
                      ref.read(selectedFolderProvider.notifier).state = folder;
                      Navigator.pop(context);
                    },
                  )),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.amber),
              title: const Text('Private Vault'),
              onTap: () async {
                Navigator.pop(context);
                final success = await ref.read(biometricProvider.notifier).authenticate();
                if (success) {
                  if (context.mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const VaultScreen()));
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Authentication failed'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Trash / Deleted'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const TrashScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).signOut();
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                onChanged: (val) => ref.read(searchQueryProvider.notifier).state = val,
                decoration: InputDecoration(
                  hintText: 'Search title, body, or tags...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: ref.read(searchQueryProvider).isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            ref.read(searchQueryProvider.notifier).state = '';
                          },
                        )
                      : null,
                ),
              ),
            ),
            // Tags Scroll Bar
            if (allTags.isNotEmpty) ...[
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: allTags.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: const Text('All Tags'),
                          selected: selectedTag == null,
                          onSelected: (selected) {
                            if (selected) ref.read(selectedTagProvider.notifier).state = null;
                          },
                        ),
                      );
                    }
                    final tag = allTags[index - 1];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('#$tag'),
                        selected: selectedTag == tag,
                        onSelected: (selected) {
                          ref.read(selectedTagProvider.notifier).state = selected ? tag : null;
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Notes Content
            Expanded(
              child: filteredNotes.isEmpty
                  ? _buildEmptyState(context, selectedTag, selectedFolder)
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      children: [
                        if (pinnedNotes.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('PINNED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0, color: Colors.grey)),
                          ),
                          _buildNotesGrid(context, ref, pinnedNotes),
                          const SizedBox(height: 16),
                        ],
                        if (unpinnedNotes.isNotEmpty) ...[
                          if (pinnedNotes.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('RECENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0, color: Colors.grey)),
                            ),
                          _buildNotesGrid(context, ref, unpinnedNotes),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NoteEditorScreen()),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSyncIndicator(BuildContext context, WidgetRef ref, SyncState state) {
    if (state.isSyncing) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.error != null) {
      return IconButton(
        icon: const Icon(Icons.sync_problem, color: Colors.red),
        tooltip: 'Sync error: ${state.error}. Tap to retry.',
        onPressed: () => ref.read(syncProvider.notifier).syncNow(),
      );
    }

    return IconButton(
      icon: const Icon(Icons.cloud_done_outlined, color: Colors.green),
      tooltip: 'All notes synced. Last sync: ${state.lastSyncTime != null ? _formatTime(state.lastSyncTime!) : "Never"}',
      onPressed: () => ref.read(syncProvider.notifier).syncNow(),
    );
  }

  Widget _buildEmptyState(BuildContext context, String? tag, String? folder) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notes_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            tag != null
                ? 'No notes matching #$tag'
                : folder != null
                    ? 'No notes in folder "$folder"'
                    : 'No notes yet',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Tap the + button to create a new note', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNotesGrid(BuildContext context, WidgetRef ref, List<NoteEntity> notes) {
    // Basic multi-column flow matching a masonry look
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 600 ? 3 : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        return _buildNoteCard(context, ref, notes[index]);
      },
    );
  }

  Widget _buildNoteCard(BuildContext context, WidgetRef ref, NoteEntity note) {
    final plainBody = QuillHelper.toPlainText(note.body);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
        );
      },
      onLongPress: () => _showNoteContextMenu(context, ref, note),
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pin + Title
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
                        color: note.title.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    Icon(Icons.push_pin, size: 16, color: Colors.amber.shade700)
                  else if (!note.isSynced)
                    Icon(Icons.cloud_off, size: 16, color: Colors.grey.shade400),
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
                    color: plainBody.isEmpty ? Colors.grey.shade500 : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Folder & Media Indicators
              Row(
                children: [
                  if (note.folderId != null && note.folderId!.isNotEmpty) ...[
                    Icon(Icons.folder, size: 12, color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        note.folderId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                  if (note.mediaUrls.isNotEmpty) ...[
                    const Spacer(),
                    Icon(Icons.attachment, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 2),
                    Text('${note.mediaUrls.length}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNoteContextMenu(BuildContext context, WidgetRef ref, NoteEntity note) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                note.title.isEmpty ? 'Untitled' : note.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: note.isPinned ? Colors.amber.shade700 : null,
              ),
              title: Text(note.isPinned ? 'Unpin Note' : 'Pin Note'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final repo = sl<NoteRepository>();
                final updatedNote = note.copyWith(
                  isPinned: !note.isPinned,
                  updatedAt: DateTime.now(),
                  isSynced: false,
                );
                await repo.saveNote(updatedNote);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Move to Trash', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final repo = sl<NoteRepository>();
                final result = await repo.deleteNote(note.noteId);
                result.fold(
                  (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Note moved to trash'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  (failure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed: ${failure.message}'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
