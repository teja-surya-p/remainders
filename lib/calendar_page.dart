import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'repeat_utils.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _nextMonthStart(DateTime d) {
    if (d.month == 12) return DateTime(d.year + 1, 1, 1);
    return DateTime(d.year, d.month + 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final start = _monthStart(_focusedDay);
    final end = _nextMonthStart(_focusedDay);
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = end.subtract(const Duration(seconds: 1));

    final query = FirebaseFirestore.instance
        .collection('users/${user.uid}/reminders');

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          final Map<DateTime, List<_CalendarEntry>> events = {};

          for (final d in docs) {
            final data = d.data();
            final completed = (data['completed'] ?? false) as bool;
            if (completed) continue;

            final title = (data['title'] ?? '') as String;
            final desc = (data['description'] ?? '') as String;
            final repeatType =
                repeatTypeFromString(data['repeatType'] as String?);
            final repeatDays = parseRepeatDays(data['repeatDays']);
            final repeatTime = (data['repeatTime'] as num?)?.toInt();
            final isRepeating =
                repeatType != RepeatType.none && repeatDays.isNotEmpty;

            if (isRepeating) {
              final dueTs = data['dueAt'];
              final fallback =
                  dueTs is Timestamp ? dueTs.toDate() : DateTime.now();
              final minutes = repeatTime ?? minutesOfDay(fallback);
              final occurrences = occurrencesInRange(
                start: rangeStart,
                end: rangeEnd,
                type: repeatType,
                days: repeatDays,
                minutes: minutes,
              );
              for (final occ in occurrences) {
                final day = _dayOnly(occ);
                events.putIfAbsent(day, () => []).add(
                      _CalendarEntry(
                        title: title,
                        description: desc.trim().isEmpty ? null : desc,
                        when: occ,
                        isRepeating: true,
                      ),
                    );
              }
            } else {
              final dueTs = data['dueAt'];
              if (dueTs is! Timestamp) continue;
              final dueAt = dueTs.toDate();
              if (dueAt.isBefore(rangeStart) || dueAt.isAfter(rangeEnd)) {
                continue;
              }
              final day = _dayOnly(dueAt);
              events.putIfAbsent(day, () => []).add(
                    _CalendarEntry(
                      title: title,
                      description: desc.trim().isEmpty ? null : desc,
                      when: dueAt,
                      isRepeating: false,
                    ),
                  );
            }
          }

          final selectedDay = _selectedDay ?? _dayOnly(DateTime.now());
          final selectedEvents =
              events[_dayOnly(selectedDay)] ?? const <_CalendarEntry>[];

          return Column(
            children: [
              TableCalendar<_CalendarEntry>(
                firstDay: DateTime(DateTime.now().year - 1, 1, 1),
                lastDay: DateTime(DateTime.now().year + 2, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) =>
                    isSameDay(_selectedDay, day),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) {
                  setState(() {
                    _focusedDay = focused;
                  });
                },
                eventLoader: (day) =>
                    events[_dayOnly(day)] ?? const <_CalendarEntry>[],
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6, bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          items.length.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: selectedEvents.isEmpty
                    ? const Center(child: Text('No alarms for this day'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: selectedEvents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final item = selectedEvents[i];

                          return ListTile(
                            tileColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(item.title)),
                                if (item.isRepeating)
                                  const _RepeatDot(),
                              ],
                            ),
                            subtitle: Text(
                              DateFormat('EEE, MMM d • h:mm a')
                                  .format(item.when),
                            ),
                            trailing: (item.description ?? '').trim().isEmpty
                                ? null
                                : Tooltip(
                                    message: item.description,
                                    child: const Icon(Icons.notes),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CalendarEntry {
  final String title;
  final String? description;
  final DateTime when;
  final bool isRepeating;

  const _CalendarEntry({
    required this.title,
    required this.when,
    required this.isRepeating,
    this.description,
  });
}

class _RepeatDot extends StatelessWidget {
  const _RepeatDot();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        'R',
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
