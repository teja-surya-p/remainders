import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import '../shared_reminder_service.dart';
import '../theme/app_tokens.dart';

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
  bool _shareTab = true;

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
      await SharedReminderService.joinByInvite(_inviteCode.text.trim());
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
      return Scaffold(
        appBar: AppBar(title: const Text('Share & Invite')),
        body: const AppEmptyState(
          icon: Icons.lock_person_rounded,
          title: 'Sign in required',
          message: 'You need an authenticated account to use sharing.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Share & Invite')),
      body: StreamBuilder<List<ReminderModel>>(
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
              Row(
                children: [
                  Expanded(
                    child: _TopSwitch(
                      label: 'Share link',
                      selected: _shareTab,
                      onTap: () => setState(() => _shareTab = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TopSwitch(
                      label: 'Join with link',
                      selected: !_shareTab,
                      onTap: () => setState(() => _shareTab = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_shareTab)
                _ShareTab(
                  active: active,
                  busy: _busy,
                  selectedReminderId: _selectedReminderId,
                  createdInviteLink: _createdInviteLink,
                  onReminderChanged: (v) =>
                      setState(() => _selectedReminderId = v),
                  onCreate: _create,
                )
              else
                _JoinTab(busy: _busy, inviteCode: _inviteCode, onJoin: _join),
              const SizedBox(height: 12),
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
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppSurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.reminderTitle,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTone.of(
                                            context,
                                          ).success.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Active',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: AppTone.of(
                                                  context,
                                                ).success,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Owner: ${item.ownerUid}\nParticipants: ${item.participantUids.length}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  AppInlineMessage(
                                    text: 'Invite code: ${item.inviteCode}',
                                    icon: Icons.key_rounded,
                                  ),
                                ],
                              ),
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
                  icon: Icons.workspace_premium_rounded,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ShareTab extends StatelessWidget {
  final List<ReminderModel> active;
  final bool busy;
  final String? selectedReminderId;
  final String? createdInviteLink;
  final ValueChanged<String?> onReminderChanged;
  final Future<void> Function() onCreate;

  const _ShareTab({
    required this.active,
    required this.busy,
    required this.selectedReminderId,
    required this.createdInviteLink,
    required this.onReminderChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Invite Link',
            subtitle: 'Generate a share link from an active reminder',
          ),
          const SizedBox(height: 8),
          if (active.isEmpty)
            const AppInlineMessage(
              text: 'Create a reminder first to share it.',
              icon: Icons.info_outline,
            )
          else
            DropdownButtonFormField<String>(
              initialValue: selectedReminderId,
              onChanged: onReminderChanged,
              items: active
                  .map(
                    (r) => DropdownMenuItem(value: r.id, child: Text(r.title)),
                  )
                  .toList(growable: false),
              decoration: const InputDecoration(labelText: 'Reminder'),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy || active.isEmpty ? null : () => onCreate(),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Generate Invite Code'),
          ),
          if ((createdInviteLink ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            AppSurfaceCard(
              dense: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      createdInviteLink!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: createdInviteLink!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinTab extends StatelessWidget {
  final bool busy;
  final TextEditingController inviteCode;
  final Future<void> Function() onJoin;

  const _JoinTab({
    required this.busy,
    required this.inviteCode,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Join a Shared Reminder',
            subtitle: 'Paste invite code or link',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: inviteCode,
            decoration: const InputDecoration(
              labelText: 'Invite code or link',
              hintText: 'snooze.app/invite/abcd1234',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: busy ? null : () => onJoin(),
            child: const Text('Join Reminder'),
          ),
        ],
      ),
    );
  }
}

class _TopSwitch extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopSwitch({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      dense: true,
      color: selected ? cs.surface : cs.secondary.withValues(alpha: 0.58),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? cs.onSurface : AppTone.of(context).mutedText,
          ),
        ),
      ),
    );
  }
}
