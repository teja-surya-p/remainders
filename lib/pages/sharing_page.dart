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

enum _SharingTab { shareLink, joinLink, reminders }

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
  _SharingTab _activeTab = _SharingTab.shareLink;

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
      final link = await SharedReminderService.createSharedReminder(
        _selectedReminderId!,
      );
      if (!mounted) return;
      setState(() => _createdInviteLink = link);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      if (e is PremiumRequiredException) {
        widget.onOpenSubscription();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
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
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copyToClipboard(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSharedReminderMembers(SharedReminder reminder) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final participants = <String>{
      reminder.ownerUid,
      ...reminder.participantUids,
    }.toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(
                title: reminder.reminderTitle,
                subtitle:
                    '${participants.length} users have access to this reminder',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: participants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final uid = participants[index];
                    final isOwner = uid == reminder.ownerUid;
                    final isYou = uid == currentUid;
                    final role = isOwner ? 'Owner' : 'Participant';
                    final suffix = isYou ? ' • You' : '';
                    return AppSurfaceCard(
                      dense: true,
                      child: Row(
                        children: [
                          Icon(
                            isOwner
                                ? Icons.shield_rounded
                                : Icons.person_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$role$suffix',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  uid,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                _copyToClipboard(uid, 'User ID copied'),
                            icon: const Icon(Icons.copy_rounded),
                            tooltip: 'Copy user ID',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
                      selected: _activeTab == _SharingTab.shareLink,
                      onTap: () =>
                          setState(() => _activeTab = _SharingTab.shareLink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TopSwitch(
                      label: 'Join with link',
                      selected: _activeTab == _SharingTab.joinLink,
                      onTap: () =>
                          setState(() => _activeTab = _SharingTab.joinLink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TopSwitch(
                      label: 'Remainders',
                      selected: _activeTab == _SharingTab.reminders,
                      onTap: () =>
                          setState(() => _activeTab = _SharingTab.reminders),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_activeTab == _SharingTab.shareLink)
                _ShareTab(
                  active: active,
                  busy: _busy,
                  selectedReminderId: _selectedReminderId,
                  createdInviteLink: _createdInviteLink,
                  onReminderChanged: (v) =>
                      setState(() => _selectedReminderId = v),
                  onCreate: _create,
                  onCopy: _copyToClipboard,
                )
              else if (_activeTab == _SharingTab.joinLink)
                _JoinTab(busy: _busy, inviteCode: _inviteCode, onJoin: _join)
              else
                _SharedRemindersTab(
                  currentUid: user.uid,
                  onOpenParticipants: _showSharedReminderMembers,
                  onCopy: _copyToClipboard,
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
  final Future<void> Function(String value, String message) onCopy;

  const _ShareTab({
    required this.active,
    required this.busy,
    required this.selectedReminderId,
    required this.createdInviteLink,
    required this.onReminderChanged,
    required this.onCreate,
    required this.onCopy,
  });

  String _extractInviteCode(String inviteLink) {
    final uri = Uri.tryParse(inviteLink);
    if (uri == null) return '';
    final queryCode = uri.queryParameters['code']?.trim();
    if (queryCode != null && queryCode.isNotEmpty) {
      return queryCode.toUpperCase();
    }
    for (final segment in uri.pathSegments.reversed) {
      final part = segment.trim();
      if (part.isNotEmpty) {
        return part.toUpperCase();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final inviteLink = (createdInviteLink ?? '').trim();
    final inviteCode = inviteLink.isEmpty ? '' : _extractInviteCode(inviteLink);
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
            label: const Text('Generate Invite Link'),
          ),
          if (inviteLink.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppSurfaceCard(
              dense: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      inviteLink,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => onCopy(inviteLink, 'Invite link copied'),
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy',
                  ),
                ],
              ),
            ),
            if (inviteCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              AppSurfaceCard(
                dense: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Invite code: $inviteCode',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onCopy(inviteCode, 'Invite code copied'),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy invite code',
                    ),
                  ],
                ),
              ),
            ],
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
              hintText: 'https://snooze.app/invite/ABCD1234?sid=...',
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

class _SharedRemindersTab extends StatelessWidget {
  final String currentUid;
  final Future<void> Function(SharedReminder reminder) onOpenParticipants;
  final Future<void> Function(String value, String message) onCopy;

  const _SharedRemindersTab({
    required this.currentUid,
    required this.onOpenParticipants,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SharedReminder>>(
      stream: SharedReminderService.watchMine(currentUid),
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
            message: 'Create an invite code or join one to collaborate.',
          );
        }
        return Column(
          children: [
            const AppSectionHeader(
              title: 'Shared Reminders',
              subtitle: 'Tap any reminder to see all users with access',
            ),
            const SizedBox(height: 8),
            ...shared.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppSurfaceCard(
                  onTap: () => onOpenParticipants(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.reminderTitle,
                              style: Theme.of(context).textTheme.titleSmall,
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
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Active',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppTone.of(context).success,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Owner: ${item.ownerUid == currentUid ? 'You' : item.ownerUid}\nParticipants: ${item.participantUids.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      AppSurfaceCard(
                        dense: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.key_rounded, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Invite code: ${item.inviteCode}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  onCopy(item.inviteCode, 'Invite code copied'),
                              icon: const Icon(Icons.copy_rounded),
                              tooltip: 'Copy invite code',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to view users who can access this reminder',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTone.of(context).mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
