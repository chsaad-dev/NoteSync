import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/injection_container.dart';
import '../../domain/entities/note_entity.dart';
import '../../domain/repository/note_repository.dart';
import '../../domain/usecases/watch_notes.dart';

// Search Query State
final searchQueryProvider = StateProvider<String>((ref) => '');

// Selected Tag State for Filtering
final selectedTagProvider = StateProvider<String?>((ref) => null);

// Selected Folder State for Filtering
final selectedFolderProvider = StateProvider<String?>((ref) => null);

// Stream of all active (non-deleted) Notes from Local DB
final notesStreamProvider = StreamProvider<List<NoteEntity>>((ref) {
  final watchNotes = sl<WatchNotes>();
  return watchNotes();
});

// Stream of all soft-deleted (Trash) Notes from Local DB
final trashStreamProvider = StreamProvider<List<NoteEntity>>((ref) {
  final repo = sl<NoteRepository>();
  return repo.watchTrash();
});

// Filtered Notes Provider (combines Search, Pins, Folders, and Tags)
final filteredNotesProvider = Provider<List<NoteEntity>>((ref) {
  final notesAsync = ref.watch(notesStreamProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final selectedTag = ref.watch(selectedTagProvider);
  final selectedFolder = ref.watch(selectedFolderProvider);

  return notesAsync.maybeWhen(
    data: (notes) {
      return notes.where((note) {
        final matchesQuery = query.isEmpty ||
            note.title.toLowerCase().contains(query) ||
            note.body.toLowerCase().contains(query) ||
            note.tags.any((t) => t.toLowerCase().contains(query));
            
        final matchesTag = selectedTag == null || note.tags.contains(selectedTag);
        final matchesFolder = selectedFolder == null || note.folderId == selectedFolder;

        return matchesQuery && matchesTag && matchesFolder;
      }).toList();
    },
    orElse: () => [],
  );
});

// Extracted list of all unique Tags across all active notes (for UI tags slider)
final allTagsProvider = Provider<List<String>>((ref) {
  final notesAsync = ref.watch(notesStreamProvider);
  return notesAsync.maybeWhen(
    data: (notes) {
      final tagsSet = <String>{};
      for (final note in notes) {
        tagsSet.addAll(note.tags);
      }
      return tagsSet.toList()..sort();
    },
    orElse: () => [],
  );
});

// Extracted list of all unique folders
final allFoldersProvider = Provider<List<String>>((ref) {
  final notesAsync = ref.watch(notesStreamProvider);
  return notesAsync.maybeWhen(
    data: (notes) {
      final foldersSet = <String>{};
      for (final note in notes) {
        if (note.folderId != null && note.folderId!.isNotEmpty) {
          foldersSet.add(note.folderId!);
        }
      }
      return foldersSet.toList()..sort();
    },
    orElse: () => [],
  );
});
