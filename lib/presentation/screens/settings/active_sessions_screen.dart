import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../../core/security/session_manager.dart';

class ActiveSessionsScreen extends ConsumerStatefulWidget {
  const ActiveSessionsScreen({super.key});

  @override
  ConsumerState<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends ConsumerState<ActiveSessionsScreen> {
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadCurrentDeviceId();
  }

  Future<void> _loadCurrentDeviceId() async {
    final id = await SessionManager.getDeviceId();
    if (mounted) {
      setState(() {
        _currentDeviceId = id;
      });
    }
  }

  String _formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown';
    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative) return 'Just now';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  void _revokeSession(BuildContext context, String uid, String deviceId, String deviceModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Session?'),
        content: Text('Are you sure you want to sign out and disconnect "$deviceModel" remotely?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              // Delete session document in Firestore
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('sessions')
                  .doc(deviceId)
                  .delete();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Session for "$deviceModel" revoked'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (authState is! Authenticated) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    final uid = authState.user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Sessions'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .orderBy('lastActiveAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading sessions: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No active sessions found'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final deviceId = data['deviceId'] as String? ?? '';
              final deviceModel = data['deviceModel'] as String? ?? 'Unknown Device';
              final osVersion = data['osVersion'] as String? ?? 'Unknown OS';
              
              final timestamp = data['lastActiveAt'] as Timestamp?;
              final lastActive = timestamp?.toDate();

              final isCurrent = deviceId == _currentDeviceId;

              return Card(
                elevation: isCurrent ? 2.0 : 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isCurrent 
                      ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                      : BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      Icon(
                        isCurrent ? Icons.phone_android : Icons.devices_other,
                        size: 36,
                        color: isCurrent 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    deviceModel,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'This device',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              osVersion,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active: ${_formatRelativeTime(lastActive)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      if (!isCurrent)
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.red),
                          tooltip: 'Revoke session',
                          onPressed: () => _revokeSession(context, uid, deviceId, deviceModel),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
