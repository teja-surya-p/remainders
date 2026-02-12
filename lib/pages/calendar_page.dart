import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../repeat_utils.dart';

class CalendarPage extends StatefulWidget {
  final VoidCallback? onOpenSubscription;

  const CalendarPage({super.key, this.onOpenSubscription});

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
    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AppLoadingIndicator(label: 'Loading calendar...');
        }

        final start = _monthStart(_focusedDay);
        final end = _nextMonthStart(
          _focusedDay,
        ).subtract(const Duration(seconds: 1));

        final reminders = snap.data!;
        final events = <DateTime, List<_CalendarEntry>>{};

        for (final reminder in reminders) {
          if (reminder.recurrence.isRepeating) {
            final minutes = reminder.recurrence.timesOfDay.isNotEmpty
                ? reminder.recurrence.timesOfDay.first
                : minutesOfDay(reminder.dueAt);
            final occ = occurrencesInRange(
              start: start,
              end: end,
              type: reminder.recurrence.type,
              days: reminder.recurrence.weekdays,
              minutes: minutes,
              intervalDays: reminder.recurrence.intervalDays,
              timesOfDay: reminder.recurrence.timesOfDay,
              anchorDate: reminder.dueAt,
              endAt: reminder.recurrence.endAt,
            );
            for (final when in occ) {
              final day = _dayOnly(when);
              events
                  .putIfAbsent(day, () => [])
                  .add(
                    _CalendarEntry(
                      title: reminder.title,
                      description: reminder.description,
                      when: when,
                      isRepeating: true,
                    ),
                  );
            }
          } else {
            final dueAt = reminder.dueAt;
            if (dueAt.isBefore(start) || dueAt.isAfter(end)) continue;
            final day = _dayOnly(dueAt);
            events
                .putIfAbsent(day, () => [])
                .add(
                  _CalendarEntry(
                    title: reminder.title,
                    description: reminder.description,
                    when: dueAt,
                    isRepeating: false,
                  ),
                );
          }
        }

        for (final list in events.values) {
          list.sort((a, b) => a.when.compareTo(b.when));
        }

        final selectedDay = _selectedDay ?? _dayOnly(DateTime.now());
        final selectedEvents =
            events[_dayOnly(selectedDay)] ?? const <_CalendarEntry>[];
        final selectedTitle = DateFormat('EEE, MMM d').format(selectedDay);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: AppSurfaceCard(
                dense: true,
                padding: const EdgeInsets.all(10),
                child: TableCalendar<_CalendarEntry>(
                  firstDay: DateTime(DateTime.now().year - 1, 1, 1),
                  lastDay: DateTime(DateTime.now().year + 2, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            items.length.toString(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: AppSectionHeader(
                title: selectedTitle,
                subtitle:
                    '${selectedEvents.length} alarm${selectedEvents.length == 1 ? '' : 's'} scheduled',
              ),
            ),
            Expanded(
              child: selectedEvents.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.event_available,
                      title: 'No alarms for this day',
                      message:
                          'Select another date or create a new reminder from the Reminders tab.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: selectedEvents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = selectedEvents[i];
                        return AppSurfaceCard(
                          dense: true,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Expanded(child: Text(item.title)),
                                if (item.isRepeating) const _RepeatDot(),
                              ],
                            ),
                            subtitle: Text(
                              DateFormat(
                                'EEE, MMM d • h:mm a',
                              ).format(item.when),
                            ),
                            trailing: (item.description ?? '').trim().isEmpty
                                ? null
                                : Tooltip(
                                    message: item.description,
                                    child: const Icon(Icons.notes),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
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
      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
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
