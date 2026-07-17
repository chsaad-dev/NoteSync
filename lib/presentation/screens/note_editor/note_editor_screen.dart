import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../domain/entities/note_entity.dart';
import '../../../domain/repository/note_repository.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/utils/quill_helper.dart';
import '../../providers/editor_provider.dart';
import '../../providers/biometric_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/user_profile_provider.dart';
import 'package:video_player/video_player.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final NoteEntity? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _folderController = TextEditingController();
  final _tagInputController = TextEditingController();
  final _editorFocusNode = FocusNode();
  QuillController? _quillController;
  final ImagePicker _imagePicker = ImagePicker();
  bool _initialized = false;
  AutocompleteTrigger? _activeTrigger;

  @override
  void initState() {
    super.initState();
    // Initialize editor state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(noteEditorProvider.notifier).initNote(widget.note);
      final editorState = ref.read(noteEditorProvider);
      final note = editorState.note;
      
      if (note != null) {
        _titleController.text = note.title;
        _folderController.text = note.folderId ?? '';
        
        final bodyText = note.body;
        if (bodyText.startsWith('[')) {
          try {
            final deltaJson = jsonDecode(bodyText) as List<dynamic>;
            _quillController = QuillController(
              document: Document.fromJson(deltaJson),
              selection: const TextSelection.collapsed(offset: 0),
            );
          } catch (_) {
            _quillController = QuillController.basic();
          }
        } else {
          _quillController = QuillController(
            document: Document()..insert(0, bodyText),
            selection: const TextSelection.collapsed(offset: 0),
          );
        }

        // Listen for quill changes
        _quillController!.document.changes.listen((_) {
          final contentJson = jsonEncode(_quillController!.document.toDelta().toJson());
          ref.read(noteEditorProvider.notifier).updateNoteContent(body: contentJson);
        });

        _quillController!.addListener(_onEditorStateChanged);

        setState(() {
          _initialized = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _folderController.dispose();
    _tagInputController.dispose();
    _editorFocusNode.dispose();
    _quillController?.removeListener(_onEditorStateChanged);
    _quillController?.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    if (tag.trim().isEmpty) return;
    final editorState = ref.read(noteEditorProvider);
    final note = editorState.note;
    if (note == null) return;

    final cleanedTag = tag.trim().toLowerCase();
    if (!note.tags.contains(cleanedTag)) {
      final updatedTags = List<String>.from(note.tags)..add(cleanedTag);
      ref.read(noteEditorProvider.notifier).updateNoteContent(tags: updatedTags);
    }
    _tagInputController.clear();
  }

  void _removeTag(String tag) {
    final editorState = ref.read(noteEditorProvider);
    final note = editorState.note;
    if (note == null) return;

    final updatedTags = List<String>.from(note.tags)..remove(tag);
    ref.read(noteEditorProvider.notifier).updateNoteContent(tags: updatedTags);
  }

  void _pickMedia() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile != null && profile.usedStorage >= profile.maxStorage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warning: Cloud storage quota exceeded. Image/video uploads are disabled.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Attach Image'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (image != null) {
                  ref.read(noteEditorProvider.notifier).attachMedia(image.path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Attach Video'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? video = await _imagePicker.pickVideo(source: ImageSource.gallery);
                if (video != null) {
                  ref.read(noteEditorProvider.notifier).attachMedia(video.path);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: const Text('This note will be moved to the trash. You can restore it later from the Trash screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final repo = sl<NoteRepository>();
              final noteId = ref.read(noteEditorProvider).note?.noteId;
              if (noteId != null) {
                final result = await repo.deleteNote(noteId);
                if (mounted) {
                  result.fold(
                    (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Note moved to trash'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      Navigator.pop(context); // Exit the editor
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
                }
              }
            },
            child: const Text('Move to Trash', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action, WidgetRef ref, NoteEntity note) async {
    switch (action) {
      case 'lock':
        final isLocking = !note.isVault;
        if (isLocking) {
          final success = await ref.read(biometricProvider.notifier).authenticate();
          if (success) {
            ref.read(noteEditorProvider.notifier).updateNoteContent(isVault: true);
            await ref.read(noteEditorProvider.notifier).save();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Note locked in Private Vault'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.pop(context);
            }
          }
        } else {
          final success = await ref.read(biometricProvider.notifier).authenticate();
          if (success) {
            ref.read(noteEditorProvider.notifier).updateNoteContent(isVault: false);
            await ref.read(noteEditorProvider.notifier).save();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Note unlocked from Private Vault'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
        break;
      case 'share':
        final plainText = QuillHelper.toPlainText(note.body);
        final titleText = note.title.isNotEmpty ? note.title : 'Untitled';
        await Share.share('$titleText\n\n$plainText');
        break;
      case 'export_md':
        final plainText = QuillHelper.toPlainText(note.body);
        final titleText = note.title.isNotEmpty ? note.title : 'Untitled';
        final markdown = '# $titleText\n\n$plainText';
        await _exportFile(titleText, markdown, '.md');
        break;
      case 'export_txt':
        final plainText = QuillHelper.toPlainText(note.body);
        final titleText = note.title.isNotEmpty ? note.title : 'Untitled';
        final content = '$titleText\n\n$plainText';
        await _exportFile(titleText, content, '.txt');
        break;
      case 'public_share':
        _showPublicLinkDialog(context, ref, note);
        break;
    }
  }

  void _showPublicLinkDialog(BuildContext context, WidgetRef ref, NoteEntity note) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, child) {
            final editorState = ref.watch(noteEditorProvider);
            final currentNote = editorState.note ?? note;
            final isSaving = editorState.isSaving;

            final workerUrl = dotenv.env['CLOUDFLARE_WORKER_URL'] ?? 'https://your-worker-url.workers.dev';
            final publicUrl = '$workerUrl/public/note/${currentNote.publicUrlId}';

            return AlertDialog(
              title: const Text('Public Web Link'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Generating a public link uploads a decrypted copy of this note to a secure Cloudflare endpoint, allowing anyone with the link to view it.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  if (currentNote.isPublic) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SelectableText(
                        publicUrl,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.grey, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Sharing is currently disabled',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                if (isSaving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                  if (currentNote.isPublic) ...[
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: publicUrl));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied to clipboard')),
                          );
                        }
                      },
                      child: const Text('Copy Link'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        await ref.read(noteEditorProvider.notifier).unpublishNote();
                      },
                      child: const Text('Disable Link'),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: () async {
                        await ref.read(noteEditorProvider.notifier).publishNote();
                      },
                      child: const Text('Enable Link'),
                    ),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportFile(String title, String content, String extension) async {
    try {
      final directory = await getTemporaryDirectory();
      final safeTitle = title.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
      final filename = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final file = File('${directory.path}/$filename');
      await file.writeAsString(content);

      final xFile = XFile(file.path);
      await Share.shareXFiles([xFile], text: 'Exported Note: $title');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _pickReminder(BuildContext context, NoteEntity note) async {
    if (note.reminderAt != null) {
      final formattedTime = '${note.reminderAt!.day}/${note.reminderAt!.month}/${note.reminderAt!.year} ${note.reminderAt!.hour.toString().padLeft(2, '0')}:${note.reminderAt!.minute.toString().padLeft(2, '0')}';
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Manage Reminder'),
          content: Text('A reminder is currently set for:\n$formattedTime'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                ref.read(noteEditorProvider.notifier).updateNoteContent(clearReminder: true);
                ref.read(noteEditorProvider.notifier).save();
              },
              child: const Text('Remove Reminder', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _selectDateTime(context, note);
              },
              child: const Text('Change Time'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      _selectDateTime(context, note);
    }
  }

  void _selectDateTime(BuildContext context, NoteEntity note) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );

    if (time == null) return;

    final selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (selectedDateTime.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a future date and time'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    ref.read(noteEditorProvider.notifier).updateNoteContent(reminderAt: selectedDateTime);
    ref.read(noteEditorProvider.notifier).save();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder set successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onEditorStateChanged() {
    final trigger = _checkAutocompleteTrigger();
    if (trigger?.trigger != _activeTrigger?.trigger || trigger?.query != _activeTrigger?.query) {
      setState(() {
        _activeTrigger = trigger;
      });
    }
  }

  AutocompleteTrigger? _checkAutocompleteTrigger() {
    if (_quillController == null) return null;
    final selection = _quillController!.selection;
    if (!selection.isCollapsed) return null;

    final cursor = selection.extentOffset;
    if (cursor <= 0) return null;

    final plainText = _quillController!.document.toPlainText();
    final startInspect = cursor > 30 ? cursor - 30 : 0;
    final textToInspect = plainText.substring(startInspect, cursor);

    final doubleBracketRegExp = RegExp(r'\[\[([^\]]*)$');
    final doubleBracketMatch = doubleBracketRegExp.firstMatch(textToInspect);
    if (doubleBracketMatch != null) {
      final query = doubleBracketMatch.group(1) ?? '';
      final triggerOffset = textToInspect.indexOf('[[');
      return AutocompleteTrigger(
        trigger: '[[',
        query: query,
        startIndex: startInspect + triggerOffset,
      );
    }

    final atRegExp = RegExp(r'@([a-zA-Z0-9\s]*)$');
    final atMatch = atRegExp.firstMatch(textToInspect);
    if (atMatch != null) {
      final query = atMatch.group(1) ?? '';
      final triggerOffset = textToInspect.lastIndexOf('@');
      if (triggerOffset == 0 || RegExp(r'\s').hasMatch(textToInspect[triggerOffset - 1])) {
        return AutocompleteTrigger(
          trigger: '@',
          query: query,
          startIndex: startInspect + triggerOffset,
        );
      }
    }

    return null;
  }

  void _insertNoteLink(NoteEntity targetNote) {
    if (_activeTrigger == null) return;

    final trigger = _activeTrigger!;
    final linkText = targetNote.title.isNotEmpty ? targetNote.title : 'Untitled Note';
    final replaceIndex = trigger.startIndex;
    final replaceLength = (trigger.trigger.length + trigger.query.length);

    _quillController!.replaceText(
      replaceIndex,
      replaceLength,
      linkText,
      null,
    );

    _quillController!.formatText(
      replaceIndex,
      linkText.length,
      LinkAttribute('notesync://notes/${targetNote.noteId}'),
    );

    _quillController!.updateSelection(
      TextSelection.collapsed(offset: replaceIndex + linkText.length),
      ChangeSource.local,
    );

    setState(() {
      _activeTrigger = null;
    });
  }

  void _openLinkedNote(BuildContext context, WidgetRef ref, String noteId) async {
    final repo = sl<NoteRepository>();
    final result = await repo.getNoteById(noteId);
    result.fold(
      (note) {
        if (note != null) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Linked note does not exist or was deleted'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      (failure) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load linked note: ${failure.message}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(noteEditorProvider);
    final note = editorState.note;
    final notesAsync = ref.watch(notesStreamProvider);

    // Dynamic autocomplete filters
    List<NoteEntity> matchingNotes = [];
    if (_activeTrigger != null) {
      final query = _activeTrigger!.query.toLowerCase().trim();
      notesAsync.whenData((allNotes) {
        matchingNotes = allNotes.where((n) {
          if (n.noteId == note?.noteId) return false;
          final title = n.title.toLowerCase();
          final plainBody = QuillHelper.toPlainText(n.body).toLowerCase();
          return title.contains(query) || plainBody.contains(query);
        }).toList();
      });
    }

    // Build list of backlinks
    final backlinks = <NoteEntity>[];
    if (note != null) {
      notesAsync.whenData((allNotes) {
        for (final n in allNotes) {
          if (n.noteId == note.noteId) continue;
          if (n.body.contains('notesync://notes/${note.noteId}')) {
            backlinks.add(n);
          }
        }
      });
    }

    ref.listen<String?>(
      noteEditorProvider.select((s) => s.error),
      (previous, next) {
        if (next != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );

    if (!_initialized || note == null || _quillController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: note.isPinned ? Colors.amber.shade700 : null,
            ),
            onPressed: () {
              ref.read(noteEditorProvider.notifier).updateNoteContent(isPinned: !note.isPinned);
            },
          ),
          IconButton(
            icon: Icon(
              note.reminderAt != null ? Icons.notifications_active : Icons.notifications_none_outlined,
              color: note.reminderAt != null ? Colors.amber.shade700 : null,
            ),
            tooltip: note.reminderAt != null ? 'Manage Reminder' : 'Set Reminder',
            onPressed: () => _pickReminder(context, note),
          ),
          IconButton(
            icon: const Icon(Icons.attachment),
            onPressed: _pickMedia,
          ),
          // Only show delete button for existing notes (not brand new ones)
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Move to Trash',
              onPressed: () => _confirmDelete(context),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(value, ref, note),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'lock',
                child: Row(
                  children: [
                    Icon(
                      note.isVault ? Icons.lock_open : Icons.lock_outline,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Text(note.isVault ? 'Unlock Note' : 'Lock Note'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('Share Text'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_md',
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('Export as Markdown (.md)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_txt',
                child: Row(
                  children: [
                    Icon(Icons.text_snippet, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Export as Plain Text (.txt)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'public_share',
                child: Row(
                  children: [
                    Icon(
                      note.isPublic ? Icons.public : Icons.public_off,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(note.isPublic ? 'Public Web Link' : 'Publish Note'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              await ref.read(noteEditorProvider.notifier).save();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Save status / Progress
            if (editorState.isSaving)
              const LinearProgressIndicator(minHeight: 2)
            else if (editorState.isUploadingMedia)
              Column(
                children: [
                  LinearProgressIndicator(value: editorState.uploadProgress, minHeight: 3, color: Colors.pink),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      'Uploading asset... ${(editorState.uploadProgress * 100).toInt()}%',
                      style: const TextStyle(fontSize: 11, color: Colors.pink, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            else
              const SizedBox(height: 2),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title Input
                    TextField(
                      controller: _titleController,
                      onChanged: (val) => ref.read(noteEditorProvider.notifier).updateNoteContent(title: val),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Folder Row
                    Row(
                      children: [
                        Icon(Icons.folder_open, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _folderController,
                            onChanged: (val) => ref.read(noteEditorProvider.notifier).updateNoteContent(folderId: val.trim()),
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                            decoration: const InputDecoration(
                              hintText: 'Add to folder (e.g. Work, Personal)',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Tags editor row (Moved from bottom toolbar!)
                    Row(
                      children: [
                        const Icon(Icons.local_offer_outlined, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ...note.tags.map((tag) => Padding(
                                      padding: const EdgeInsets.only(right: 6.0),
                                      child: InputChip(
                                        label: Text('#$tag'),
                                        onDeleted: () => _removeTag(tag),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    )),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _tagInputController,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: _addTag,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      hintText: '+ Add tag',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    
                    // Media Previews
                    if (note.mediaUrls.isNotEmpty) ...[
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: note.mediaUrls.length,
                          itemBuilder: (context, index) {
                            final url = note.mediaUrls[index];
                            final isVideo = url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.avi');
                            
                            return Stack(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (isVideo) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FullScreenVideoPlayer(videoUrl: url),
                                        ),
                                      );
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FullScreenImageViewer(imageUrl: url),
                                        ),
                                      );
                                    }
                                  },
                                  child: Hero(
                                    tag: url,
                                    child: Container(
                                      width: 120,
                                      margin: const EdgeInsets.only(right: 8.0, top: 8.0),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.shade300),
                                        image: isVideo
                                            ? null
                                            : DecorationImage(
                                                image: NetworkImage(url),
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                      child: isVideo
                                          ? const Center(child: Icon(Icons.play_circle_fill, size: 40, color: Colors.pink))
                                          : null,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () => ref.read(noteEditorProvider.notifier).removeMedia(url),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Quill Editor Rich Input (scrollable set to false inside SingleChildScrollView)
                    QuillEditor.basic(
                      controller: _quillController!,
                      focusNode: _editorFocusNode,
                      config: QuillEditorConfig(
                        placeholder: 'Start writing your note...',
                        expands: false,
                        scrollable: false,
                        padding: EdgeInsets.zero,
                        linkActionPickerDelegate: (context, link, node) async {
                          if (link.startsWith('notesync://notes/')) {
                            final noteId = link.split('notesync://notes/')[1];
                            _openLinkedNote(context, ref, noteId);
                            return LinkMenuAction.none;
                          }
                          return LinkMenuAction.launch;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Backlinks View Panel
                    if (backlinks.isNotEmpty) ...[
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Backlinks (Notes linking here)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: backlinks.map((blNote) => ActionChip(
                          avatar: Icon(Icons.link, size: 14, color: Theme.of(context).colorScheme.primary),
                          label: Text(blNote.title.isNotEmpty ? blNote.title : 'Untitled'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => NoteEditorScreen(note: blNote)),
                            );
                          },
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            
            // Autocomplete popover overlay list
            if (_activeTrigger != null && matchingNotes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingNotes.length,
                  itemBuilder: (context, index) {
                    final target = matchingNotes[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.link, size: 16, color: Colors.grey),
                      title: Text(
                        target.title.isNotEmpty ? target.title : 'Untitled Note',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: target.folderId != null && target.folderId!.isNotEmpty
                          ? Text(target.folderId!, style: const TextStyle(fontSize: 10))
                          : null,
                      onTap: () => _insertNoteLink(target),
                    );
                  },
                ),
              ),

            // Rich Text Editing Toolbar (Single compact row)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: QuillSimpleToolbar(
                controller: _quillController!,
                config: const QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showAlignmentButtons: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showHeaderStyle: false,
                  showListCheck: true,
                  showCodeBlock: false,
                  showIndent: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: false,
                  showInlineCode: false,
                  showQuote: false,
                  showDirection: false,
                  showDividers: false,
                  showSmallButton: false,
                  showRedo: false,
                  showUndo: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const FullScreenImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          clipBehavior: Clip.none,
          maxScale: 4.0,
          child: Hero(
            tag: imageUrl,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const FullScreenVideoPlayer({super.key, required this.videoUrl});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
        });
        _controller.play();
      }).catchError((_) {
        setState(() {
          _hasError = true;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Video Preview'),
      ),
      body: Center(
        child: _hasError
            ? const Text(
                'Failed to play video',
                style: TextStyle(color: Colors.white),
              )
            : !_initialized
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Hero(
                          tag: widget.videoUrl,
                          child: VideoPlayer(_controller),
                        ),
                        _ControlsOverlay(controller: _controller),
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.pink,
                            bufferedColor: Colors.grey,
                            backgroundColor: Colors.black26,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  const _ControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 50),
          reverseDuration: const Duration(milliseconds: 200),
          child: widget.controller.value.isPlaying
              ? const SizedBox.shrink()
              : Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 80.0,
                      semanticLabel: 'Play',
                    ),
                  ),
                ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              widget.controller.value.isPlaying
                  ? widget.controller.pause()
                  : widget.controller.play();
            });
          },
        ),
      ],
    );
  }
}

class AutocompleteTrigger {
  final String trigger;
  final String query;
  final int startIndex;

  AutocompleteTrigger({required this.trigger, required this.query, required this.startIndex});
}
