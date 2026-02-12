import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import '../shared_reminder_service.dart';

class SharingPage extends StatefulWidget {
  final VoidCallback onOpenSubscription;

  const SharingPage({super.key, required this.onOpenSubscription});

  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  String? _selectedReminderId;
  final TextEditingController _inviteCode = TextEditingController();
  bool _busy = false;
  String? _createdInviteLink;

  @override
  void dispose() {
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selectedReminderId == null) return;

    setState(() {
      _busy = true;
      _createdInviteLink = null;
    });

    try {
      final code = await SharedReminderService.createSharedReminder(
        _selectedReminderId!,
      );
      if (!mounted) return;
      setState(() => _createdInviteLink = code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      if (e is PremiumRequiredException) {
        widget.onOpenSubscription();
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await SharedReminderService.joinByInvite(_inviteCode.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Joined shared reminder.')));
      _inviteCode.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      if (e is PremiumRequiredException) {
        widget.onOpenSubscription();
      }
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AppEmptyState(
        icon: Icons.lock_person,
        title: 'Sign in required',
        message: 'You need an authenticated account to use sharing.',
      );
    }

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      builder: (context, reminderSnap) {
        final reminders = reminderSnap.data ?? const <ReminderModel>[];
        final active = reminders
            .where((r) => r.isActive)
            .toList(growable: false);
        _selectedReminderId ??= active.isNotEmpty ? active.first.id : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionHeader(
                    title: 'Create Shared Reminder',
                    subtitle: 'Generate an invite code from an active reminder',
                  ),
                  const SizedBox(height: 10),
                  if (active.isEmpty)
                    const AppInlineMessage(
                      text: 'Create a reminder first to share it.',
                      icon: Icons.info_outline,
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedReminderId),
                      initialValue: _selectedReminderId,
                      onChanged: (v) => setState(() => _selectedReminderId = v),
                      items: active
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.title),
                            ),
                          )
                          .toList(),
                      decoration: const InputDecoration(labelText: 'Reminder'),
                    ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _busy || active.isEmpty ? null : _create,
                    child: const Text('Generate Invite Code'),
                  ),
                  if ((_createdInviteLink ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SelectableText('Invite link: $_createdInviteLink'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionHeader(
                    title: 'Join with Invite Code',
                    subtitle: 'Paste code or full invite link',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inviteCode,
                    decoration: const InputDecoration(
                      labelText: 'Invite code or link',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _join,
                    child: const Text('Join'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const AppSectionHeader(
              title: 'Shared Reminders',
              subtitle: 'Reminders where you are owner or participant',
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<SharedReminder>>(
              stream: SharedReminderService.watchMine(user.uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const AppLoadingIndicator(
                    label: 'Loading shared reminders...',
                  );
                }
                final shared = snap.data!;
                if (shared.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.group_outlined,
                    title: 'No shared reminders yet',
                    message:
                        'Create an invite code or join one to collaborate.',
                  );
                }
                return Column(
                  children: shared
                      .map(
                        (item) => AppSurfaceCard(
                          dense: true,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.reminderTitle),
                            subtitle: Text(
                              'Owner: ${item.ownerUid}\nParticipants: ${item.participantUids.length}',
                            ),
                            trailing: Text(item.inviteCode),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            if (!AppServices.reminders.isPremiumMode) ...[
              const SizedBox(height: 12),
              const AppInlineMessage(
                text:
                    'Premium is required to create or join new shared reminders. Existing shares remain viewable.',
                icon: Icons.workspace_premium,
              ),
            ],
          ],
        );
      },
    );
  }
}
