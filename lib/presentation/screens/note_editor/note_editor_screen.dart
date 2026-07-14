import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import '../../../domain/entities/note_entity.dart';
import '../../providers/editor_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(noteEditorProvider);
    final note = editorState.note;

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
            icon: const Icon(Icons.attachment),
            onPressed: _pickMedia,
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
                                Container(
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
                      config: const QuillEditorConfig(
                        placeholder: 'Start writing your note...',
                        expands: false,
                        scrollable: false,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
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
