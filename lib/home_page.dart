import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'calendar_page.dart';
import 'notifs.dart';
import 'repeat_utils.dart';

const Duration _leadTime = Duration(minutes: 30);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  CollectionReference<Map<String, dynamic>> _remindersRef(String uid) {
    return FirebaseFirestore.instance.collection('users/$uid/reminders');
  }

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ref = _remindersRef(user.uid);

    final todayStart = _startOfToday();

    final upcomingQuery = ref
        .where('dueAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .orderBy('dueAt');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => ReminderEditorDialog(
              titleText: 'New reminder',
              onSave: (draft) async {
                final uid = FirebaseAuth.instance.currentUser!.uid;
                final ref =
                    FirebaseFirestore.instance.collection('users/$uid/reminders');

                final now = DateTime.now();
                final repeatType = draft.repeatType;
                final repeatDays = [...draft.repeatDays]..sort();
                final minutes = minutesOfDay(draft.dueAt);
                DateTime nextDueAt = draft.dueAt;

                if (repeatType != RepeatType.none) {
                  if (repeatDays.isEmpty) {
                    throw Exception('Select repeat days.');
                  }
                  final start =
                      draft.dueAt.isAfter(now) ? draft.dueAt : now;
                  final computed = nextOccurrence(
                    from: start,
                    type: repeatType,
                    days: repeatDays,
                    minutes: minutes,
                  );
                  if (computed == null) {
                    throw Exception('Invalid repeat configuration.');
                  }
                  nextDueAt = computed;
                }

                final data = <String, dynamic>{
                  'title': draft.title,
                  'description': draft.description,
                  'dueAt': Timestamp.fromDate(nextDueAt),
                  'completed': false,
                  'missed': false,
                  'createdAt': FieldValue.serverTimestamp(),
                };

                final repeatString = repeatTypeToString(repeatType);
                if (repeatString != null) {
                  data['repeatType'] = repeatString;
                  data['repeatDays'] = repeatDays;
                  data['repeatTime'] = minutes;
                }

                await ref.add(data);
              },
            ),
          );
          if (created == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Reminder added')),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CalendarPage()),
              );
            },
            icon: const Icon(Icons.calendar_month),
            label: const Text('Calendar'),
          ),
        ),
      ),
      body: SafeArea(
        child: _ReminderStreamList(query: upcomingQuery),
      ),
    );
  }
}

class _ReminderStreamList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _ReminderStreamList({required this.query});

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<bool> _confirmDelete(BuildContext context) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete reminder?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No reminders'));

        final Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
            groups = {};
        for (final doc in docs) {
          final data = doc.data();
          final dueTs = data['dueAt'];
          if (dueTs is! Timestamp) continue;
          final dueAt = dueTs.toDate();
          final day = _dayOnly(dueAt);
          groups.putIfAbsent(day, () => []).add(doc);
        }

        final days = groups.keys.toList()..sort();
        final entries = <_ListEntry>[];
        for (final day in days) {
          final list = groups[day]!;
          list.sort((a, b) {
            final aTs = a.data()['dueAt'] as Timestamp;
            final bTs = b.data()['dueAt'] as Timestamp;
            return aTs.compareTo(bTs);
          });
          entries.add(_ListEntry.header(day));
          for (final doc in list) {
            entries.add(_ListEntry.doc(doc));
          }
        }

        if (entries.isEmpty) {
          return const Center(child: Text('No reminders'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final entry = entries[i];
            if (entry.isHeader) {
              final label = DateFormat('EEE, MMM d').format(entry.day!);
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            final d = entry.doc!;
            final data = d.data();
            final title = (data['title'] ?? '') as String;
            final desc = (data['description'] ?? '') as String;
            final dueTs = data['dueAt'] as Timestamp;
            final dueAt = dueTs.toDate();
            final completed = (data['completed'] ?? false) as bool;
            final missed = (data['missed'] ?? false) as bool;
            final repeatType =
                repeatTypeFromString(data['repeatType'] as String?);
            final repeatDays = parseRepeatDays(data['repeatDays']);
            final isRepeating = repeatType != RepeatType.none;
            final mainId = (data['notifIdMain'] as num?)?.toInt();
            final preId = (data['notifIdPre'] as num?)?.toInt();
            final checked = completed || missed;

            return _ReminderTile(
              title: title,
              description: desc.trim().isEmpty ? null : desc,
              dueAt: dueAt,
              checked: checked,
              missed: missed,
              isRepeating: isRepeating,
              onTap: () async {
                await showDialog<bool>(
                  context: context,
                  builder: (_) => ReminderEditorDialog(
                    titleText: 'Edit reminder',
                    initial: ReminderDraft(
                      title: title,
                      description: desc.trim().isEmpty ? null : desc.trim(),
                      dueAt: dueAt,
                      repeatType: repeatType,
                      repeatDays: repeatDays,
                    ),
                    onSave: (draft) async {
                      final now = DateTime.now();
                      final repeatType = draft.repeatType;
                      final repeatDays = [...draft.repeatDays]..sort();
                      final minutes = minutesOfDay(draft.dueAt);
                      DateTime nextDueAt = draft.dueAt;

                      if (repeatType != RepeatType.none) {
                        if (repeatDays.isEmpty) {
                          throw Exception('Select repeat days.');
                        }
                        final start =
                            draft.dueAt.isAfter(now) ? draft.dueAt : now;
                        final computed = nextOccurrence(
                          from: start,
                          type: repeatType,
                          days: repeatDays,
                          minutes: minutes,
                        );
                        if (computed == null) {
                          throw Exception('Invalid repeat configuration.');
                        }
                        nextDueAt = computed;
                      }

                      final preTime = nextDueAt.subtract(_leadTime);
                      if (mainId != null) {
                        await Notifs.cancel(mainId);
                      }
                      if (preId != null) {
                        await Notifs.cancel(preId);
                      }
                      final nextMainId =
                          mainId ??
                          (DateTime.now().millisecondsSinceEpoch % 2147483647);
                      final nextPreId = nextMainId + 1;

                      final updates = <String, dynamic>{
                        'title': draft.title,
                        'description': draft.description,
                        'dueAt': Timestamp.fromDate(nextDueAt),
                        'completed': false,
                        'missed': false,
                        'updatedAt': FieldValue.serverTimestamp(),
                        'notifIdMain': nextMainId,
                      };

                      final repeatString = repeatTypeToString(repeatType);
                      if (repeatString != null) {
                        updates['repeatType'] = repeatString;
                        updates['repeatDays'] = repeatDays;
                        updates['repeatTime'] = minutes;
                      } else {
                        updates['repeatType'] = FieldValue.delete();
                        updates['repeatDays'] = FieldValue.delete();
                        updates['repeatTime'] = FieldValue.delete();
                      }

                      if (preTime.isAfter(now)) {
                        updates['notifIdPre'] = nextPreId;
                      } else {
                        updates['notifIdPre'] = FieldValue.delete();
                      }

                      await d.reference.update(updates);

                      if (preTime.isAfter(now)) {
                        await Notifs.schedule(
                          id: nextPreId,
                          title: 'Upcoming reminder',
                          body:
                              '${draft.title} in ${_leadTime.inMinutes} minutes',
                          whenLocal: preTime,
                          payload: 'pre:${d.id}',
                        );
                      }

                      if (nextDueAt.isAfter(now)) {
                        await Notifs.schedule(
                          id: nextMainId,
                          title: draft.title,
                          body: draft.description,
                          whenLocal: nextDueAt,
                          payload: 'alarm:${d.id}',
                          isAlarm: true,
                        );
                      }
                    },
                  ),
                );
              },
              onToggle: (val) async {
                await d.reference.update({
                  'completed': val,
                  'missed': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (val == true) {
                  if (mainId != null) {
                    await Notifs.cancel(mainId);
                  }
                  if (preId != null) {
                    await Notifs.cancel(preId);
                  }
                }
              },
              onDelete: () async {
                final ok = await _confirmDelete(context);
                if (ok) {
                  if (mainId != null) {
                    await Notifs.cancel(mainId);
                  }
                  if (preId != null) {
                    await Notifs.cancel(preId);
                  }
                  await d.reference.delete();
                }
              },
            );
          },
        );
      },
    );
  }
}

class _ListEntry {
  final DateTime? day;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  const _ListEntry.header(this.day) : doc = null;
  const _ListEntry.doc(this.doc) : day = null;

  bool get isHeader => day != null;
}

class _ReminderTile extends StatelessWidget {
  final String title;
  final String? description;
  final DateTime dueAt;
  final bool checked;
  final bool missed;
  final bool isRepeating;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _ReminderTile({
    required this.title,
    required this.description,
    required this.dueAt,
    required this.checked,
    required this.missed,
    required this.isRepeating,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: missed ? null : (v) => onToggle(v ?? false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: checked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('h:mm a').format(dueAt)),
                    if (description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isRepeating) _Badge(text: 'R', outlined: true),
              if (isRepeating) const SizedBox(width: 6),
              if (missed) _Badge(text: 'Missed'),
              if (missed) const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool outlined;
  const _Badge({required this.text, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = outlined ? Colors.transparent : cs.primaryContainer;
    final fg = outlined ? cs.primary : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: outlined ? Border.all(color: cs.primary) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class ReminderDraft {
  final String title;
  final String? description;
  final DateTime dueAt;
  final RepeatType repeatType;
  final List<int> repeatDays;

  ReminderDraft({
    required this.title,
    required this.dueAt,
    this.description,
    this.repeatType = RepeatType.none,
    List<int>? repeatDays,
  }) : repeatDays = List.unmodifiable(repeatDays ?? const []);
}

class ReminderEditorDialog extends StatefulWidget {
  final String titleText;
  final ReminderDraft? initial;
  final Future<void> Function(ReminderDraft draft) onSave;

  const ReminderEditorDialog({
    super.key,
    required this.titleText,
    required this.onSave,
    this.initial,
  });

  @override
  State<ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<ReminderEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  DateTime? _dueAt;
  late RepeatType _repeatType;
  late final Set<int> _repeatDays;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _desc = TextEditingController(text: widget.initial?.description ?? '');
    _dueAt = widget.initial?.dueAt;
    _repeatType = widget.initial?.repeatType ?? RepeatType.none;
    _repeatDays = {...(widget.initial?.repeatDays ?? const [])};
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _setRepeatType(RepeatType type) {
    setState(() {
      _repeatType = type;
      if (type == RepeatType.none) {
        _repeatDays.clear();
      } else if (_repeatDays.isEmpty) {
        final base = _dueAt ?? DateTime.now();
        _repeatDays.add(
          type == RepeatType.weekly ? base.weekday : base.day,
        );
      }
    });
  }

  void _toggleRepeatDay(int day) {
    setState(() {
      if (_repeatDays.contains(day)) {
        _repeatDays.remove(day);
      } else {
        _repeatDays.add(day);
      }
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _dueAt ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now),
    );
    if (time == null) return;

    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dueText = _dueAt == null
        ? 'Pick date & time'
        : DateFormat('EEE, MMM d • h:mm a').format(_dueAt!);

    final needsRepeatDays = _repeatType != RepeatType.none;
    final canSave = _title.text.trim().isNotEmpty &&
        _dueAt != null &&
        (!needsRepeatDays || _repeatDays.isNotEmpty);

    return AlertDialog(
      title: Text(widget.titleText),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.schedule),
                label: Text(dueText),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Repeat'),
                const Spacer(),
                DropdownButton<RepeatType>(
                  value: _repeatType,
                  onChanged: (value) {
                    if (value == null) return;
                    _setRepeatType(value);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: RepeatType.none,
                      child: Text('None'),
                    ),
                    DropdownMenuItem(
                      value: RepeatType.weekly,
                      child: Text('Weekly'),
                    ),
                    DropdownMenuItem(
                      value: RepeatType.monthly,
                      child: Text('Monthly'),
                    ),
                  ],
                ),
              ],
            ),
            if (_repeatType == RepeatType.weekly) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: List.generate(7, (i) {
                  final day = i + 1;
                  final labels = const [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun'
                  ];
                  return FilterChip(
                    label: Text(labels[i]),
                    selected: _repeatDays.contains(day),
                    onSelected: (_) => _toggleRepeatDay(day),
                  );
                }),
              ),
            ],
            if (_repeatType == RepeatType.monthly) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 160,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(31, (i) {
                      final day = i + 1;
                      return FilterChip(
                        label: Text(day.toString()),
                        selected: _repeatDays.contains(day),
                        onSelected: (_) => _toggleRepeatDay(day),
                      );
                    }),
                  ),
                ),
              ),
            ],
            if (needsRepeatDays && _repeatDays.isEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select at least one day.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !canSave || _saving
              ? null
              : () async {
                  final draft = ReminderDraft(
                    title: _title.text.trim(),
                    description:
                        _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                    dueAt: _dueAt!,
                    repeatType: _repeatType,
                    repeatDays: _repeatDays.toList(),
                  );
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await widget.onSave(draft);
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _error = 'Save failed: $e';
                    });
                  } finally {
                    if (!mounted) return;
                    setState(() {
                      _saving = false;
                    });
                  }
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
