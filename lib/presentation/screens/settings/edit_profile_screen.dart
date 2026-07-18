import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../../core/di/injection_container.dart';
import '../../../domain/repository/note_repository.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  File? _selectedImage;
  bool _isSaving = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    // Pre-fill display name when the profile data becomes available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(userProfileProvider).value;
      if (profile != null) {
        _nameController.text = profile.displayName;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Profile Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSourceOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  _buildSourceOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: theme.colorScheme.primaryContainer.withOpacity(0.2),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = ref.read(userIdProvider);
    if (uid == null) return;

    setState(() {
      _isSaving = true;
      _uploadError = null;
    });

    try {
      String? photoUrl = ref.read(userProfileProvider).value?.photoUrl;

      // 1. Upload picked image to Cloudinary if selected
      if (_selectedImage != null) {
        final repository = sl<NoteRepository>();
        final uploadResult = await repository.uploadMedia(_selectedImage!.path);
        
        uploadResult.fold(
          (url) {
            photoUrl = url;
          },
          (failure) {
            throw Exception(failure.message);
          },
        );
      }

      // 2. Save profile fields to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'displayName': _nameController.text.trim(),
            'photoUrl': photoUrl,
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _uploadError = e.toString().replaceAll('Exception:', '').trim();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProfile,
            ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Please log in to manage your profile.'));
          }

          final email = profile.email;
          final fallbackInitials = (profile.displayName.isNotEmpty ? profile.displayName : email)
              .substring(0, 1)
              .toUpperCase();

          return Stack(
            children: [
              Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
                  children: [
                    // Avatar and Edit Overlay
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                )
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 65,
                              backgroundColor: Colors.transparent,
                              child: ClipOval(
                                child: _selectedImage != null
                                    ? Image.file(
                                        _selectedImage!,
                                        width: 130,
                                        height: 130,
                                        fit: BoxFit.cover,
                                      )
                                    : (profile.photoUrl != null
                                        ? Image.network(
                                            profile.photoUrl!,
                                            width: 130,
                                            height: 130,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                _buildFallbackInitialsAvatar(fallbackInitials),
                                          )
                                        : _buildFallbackInitialsAvatar(fallbackInitials)),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Material(
                              elevation: 4.0,
                              shape: const CircleBorder(),
                              color: theme.colorScheme.primary,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _showImageSourceActionSheet(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 20,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Error Message
                    if (_uploadError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          _uploadError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Input: Display Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name cannot be empty';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Input: Email Read Only
                    TextFormField(
                      initialValue: email,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                        helperText: 'Email address cannot be changed.',
                      ),
                    ),
                  ],
                ),
              ),

              // Saving Overlay
              if (_isSaving)
                Container(
                  color: Colors.black.withOpacity(0.35),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Text(
                                _selectedImage != null
                                    ? 'Uploading picture & saving profile...'
                                    : 'Saving profile updates...',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading profile: $err')),
      ),
    );
  }

  Widget _buildFallbackInitialsAvatar(String initials) {
    final theme = Theme.of(context);
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
