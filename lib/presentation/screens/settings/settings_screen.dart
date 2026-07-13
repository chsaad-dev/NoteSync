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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
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
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Toggle between dark and light themes'),
                  trailing: Switch(
                    value: themeMode == ThemeMode.dark,
                    onChanged: (_) => ref.read(themeProvider.notifier).toggleTheme(),
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
