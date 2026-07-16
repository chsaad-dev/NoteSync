import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/biometric_provider.dart';
import '../../providers/sync_provider.dart';
import '../../../core/di/injection_container.dart';
import '../../../domain/usecases/delete_account.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Your Account?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
          'Warning: This action is permanent. All your notes in the cloud (Firestore), '
          'all uploaded images/videos (Cloudinary), and all local app data will be completely deleted. '
          'You will be signed out immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              // Show progress dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text('Deleting account data...'),
                    ],
                  ),
                ),
              );

              final deleteAccountUseCase = sl<DeleteAccount>();
              final result = await deleteAccountUseCase();

              if (context.mounted) {
                Navigator.pop(context); // Close progress dialog
                
                result.fold(
                  (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account purged successfully'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(context); // Exit settings screen
                  },
                  (failure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Purging failed: ${failure.message}'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                );
              }
            },
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
  }

  Widget _buildColorDot(WidgetRef ref, String colorKey, Color color, String activeKey) {
    final isActive = colorKey == activeKey;
    return GestureDetector(
      onTap: () => ref.read(themeProvider.notifier).setPrimaryColor(colorKey),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isActive
              ? Border.all(color: Colors.white, width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: isActive ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isActive
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final biometricState = ref.watch(biometricProvider);
    final syncState = ref.watch(syncProvider);
    final authState = ref.watch(authProvider);

    // Format last synced time
    String syncTimeText = 'Never';
    if (syncState.lastSyncTime != null) {
      final t = syncState.lastSyncTime!;
      syncTimeText = '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    // Listen to biometric error notifications
    ref.listen<String?>(
      biometricProvider.select((s) => s.error),
      (previous, next) {
        if (next != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          ref.read(biometricProvider.notifier).clearError();
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Aesthetics & Behavior
          const Text(
            'APPEARANCE & SECURITY',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Theme Mode Selector
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Theme Mode'),
                  subtitle: const Text('Select how NoteSync should look'),
                  trailing: DropdownButton<ThemeMode>(
                    value: themeState.themeMode,
                    underline: const SizedBox(),
                    onChanged: (mode) {
                      if (mode != null) {
                        ref.read(themeProvider.notifier).setThemeMode(mode);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                  ),
                ),
                // OLED Pure Black Switch (Only visible if Dark or System mode selected)
                if (themeState.themeMode != ThemeMode.light) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.brightness_2_outlined),
                    title: const Text('OLED Pure Black'),
                    subtitle: const Text('Use solid pitch black in dark theme'),
                    trailing: Switch(
                      value: themeState.isPureBlack,
                      onChanged: (val) => ref.read(themeProvider.notifier).setPureBlack(val),
                    ),
                  ),
                ],
                const Divider(height: 1),
                // Typography selector
                ListTile(
                  leading: const Icon(Icons.font_download_outlined),
                  title: const Text('Typography Font'),
                  subtitle: const Text('Change the app text style'),
                  trailing: DropdownButton<String>(
                    value: themeState.fontFamilyKey,
                    underline: const SizedBox(),
                    onChanged: (fontKey) {
                      if (fontKey != null) {
                        ref.read(themeProvider.notifier).setFontFamily(fontKey);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'sansSerif',
                        child: Text('Modern Sans'),
                      ),
                      DropdownMenuItem(
                        value: 'serif',
                        child: Text('Elegant Serif'),
                      ),
                      DropdownMenuItem(
                        value: 'monospace',
                        child: Text('Technical Mono'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Color Seed Selector
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Primary Accent Color',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildColorDot(ref, 'indigo', const Color(0xFF6366F1), themeState.primaryColorKey),
                          _buildColorDot(ref, 'teal', const Color(0xFF0D9488), themeState.primaryColorKey),
                          _buildColorDot(ref, 'pink', const Color(0xFFEC4899), themeState.primaryColorKey),
                          _buildColorDot(ref, 'amber', const Color(0xFFD97706), themeState.primaryColorKey),
                          _buildColorDot(ref, 'purple', const Color(0xFF8B5CF6), themeState.primaryColorKey),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Biometric Lock'),
                  subtitle: const Text('Protect notes with fingerprint or PIN lock'),
                  trailing: Switch(
                    value: biometricState.isEnabled,
                    onChanged: (val) => ref.read(biometricProvider.notifier).toggleBiometric(val),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Sync Config
          const Text(
            'DATA SYNCHRONIZATION',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: const Text('Sync with Cloud'),
                    subtitle: Text('Last synchronized: $syncTimeText'),
                    trailing: syncState.isSyncing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : ElevatedButton(
                            onPressed: () => ref.read(syncProvider.notifier).syncNow(),
                            style: ElevatedButton.styleFrom(elevation: 0),
                            child: const Text('Sync Now'),
                          ),
                  ),
                  if (syncState.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sync Error: ${syncState.error}',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section: Account Management
          const Text(
            'ACCOUNT MANAGEMENT',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Logged in as'),
                  subtitle: Text(
                    authState is Authenticated ? authState.user.email ?? '' : 'Offline User',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Purge all remote data and delete account permanently'),
                  onTap: () => _confirmDeleteAccount(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
