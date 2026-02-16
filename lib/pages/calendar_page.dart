import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../repeat_utils.dart';
import '../theme/app_tokens.dart';

class CalendarPage extends StatefulWidget {
  final VoidCallback? onOpenSubscription;

  const CalendarPage({super.key, this.onOpenSubscription});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDay = _dayOnly(now);
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _nextMonthStart(DateTime d) {
    if (d.month == 12) return DateTime(d.year + 1, 1, 1);
    return DateTime(d.year, d.month + 1, 1);
  }

  int _firstWeekdayOffset(DateTime month) {
    final weekday = DateTime(
      month.year,
      month.month,
      1,
    ).weekday; // Mon=1..Sun=7
    return weekday - 1;
  }

  int _daysInMonth(DateTime month) =>
      DateTime(month.year, month.month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    final tone = AppTone.of(context);
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AppLoadingIndicator(label: 'Loading calendar...');
        }

        final reminders = snap.data!;
        final start = _monthStart(_focusedMonth);
        final end = _nextMonthStart(
          _focusedMonth,
        ).subtract(const Duration(seconds: 1));

        final byDay = <DateTime, List<_CalendarEntry>>{};

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
              byDay
                  .putIfAbsent(day, () => [])
                  .add(
                    _CalendarEntry(
                      title: reminder.title,
                      description: reminder.description,
                      when: when,
                      isRepeating: true,
                      completed: reminder.completed,
                      missed: reminder.missed,
                    ),
                  );
            }
          } else {
            final dueAt = reminder.dueAt;
            if (dueAt.isBefore(start) || dueAt.isAfter(end)) continue;
            final day = _dayOnly(dueAt);
            byDay
                .putIfAbsent(day, () => [])
                .add(
                  _CalendarEntry(
                    title: reminder.title,
                    description: reminder.description,
                    when: dueAt,
                    isRepeating: false,
                    completed: reminder.completed,
                    missed: reminder.missed,
                  ),
                );
          }
        }

        for (final entries in byDay.values) {
          entries.sort((a, b) => a.when.compareTo(b.when));
        }

        final selectedEvents =
            byDay[_dayOnly(_selectedDay)] ?? const <_CalendarEntry>[];
        final daysInMonth = _daysInMonth(_focusedMonth);
        final leading = _firstWeekdayOffset(_focusedMonth);
        final totalCells = leading + daysInMonth;
        final trailing = (7 - (totalCells % 7)) % 7;
        final nowDay = _dayOnly(DateTime.now());

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 110),
          children: [
            Text(
              'Calendar',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Your reminder schedule',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tone.mutedText),
            ),
            const SizedBox(height: 10),
            AppSurfaceCard(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _focusedMonth = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month - 1,
                          1,
                        );
                      });
                    },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM y').format(_focusedMonth),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _focusedMonth = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month + 1,
                          1,
                        );
                      });
                    },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppSurfaceCard(
              dense: true,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                children: [
                  Row(
                    children: const [
                      _DayLabel('Mon'),
                      _DayLabel('Tue'),
                      _DayLabel('Wed'),
                      _DayLabel('Thu'),
                      _DayLabel('Fri'),
                      _DayLabel('Sat'),
                      _DayLabel('Sun'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: totalCells + trailing,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leading + 1;
                      if (index < leading || dayNumber > daysInMonth) {
                        return const SizedBox.shrink();
                      }

                      final day = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month,
                        dayNumber,
                      );
                      final dayOnly = _dayOnly(day);
                      final selected = dayOnly == _dayOnly(_selectedDay);
                      final isToday = dayOnly == nowDay;
                      final isPast = dayOnly.isBefore(nowDay);
                      final hasEvents = byDay.containsKey(dayOnly);

                      final entries =
                          byDay[dayOnly] ?? const <_CalendarEntry>[];
                      final completed = entries
                          .where((e) => e.completed)
                          .length;
                      final status = entries.isEmpty
                          ? null
                          : (completed == entries.length
                                ? _DotStatus.all
                                : completed > 0
                                ? _DotStatus.some
                                : _DotStatus.none);

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selectedDay = dayOnly),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: selected
                                ? cs.primary
                                : isToday
                                ? cs.primary.withValues(alpha: 0.10)
                                : Colors.transparent,
                            border: isToday && !selected
                                ? Border.all(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  )
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '$dayNumber',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: selected
                                          ? cs.onPrimary
                                          : isPast
                                          ? tone.mutedText.withValues(
                                              alpha: 0.5,
                                            )
                                          : cs.onSurface,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                              ),
                              if (hasEvents)
                                Positioned(
                                  bottom: 5,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? cs.onPrimary
                                          : status == _DotStatus.all
                                          ? tone.chart2
                                          : status == _DotStatus.some
                                          ? tone.warning
                                          : cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppSectionHeader(
              title: _selectedTitle(_selectedDay, nowDay),
              subtitle:
                  '${selectedEvents.length} reminder${selectedEvents.length == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 8),
            if (selectedEvents.isEmpty)
              AppEmptyState(
                icon: Icons.calendar_month_outlined,
                title: _dayOnly(_selectedDay).isBefore(nowDay)
                    ? 'No reminders recorded'
                    : 'No reminders scheduled',
                message: _dayOnly(_selectedDay).isBefore(nowDay)
                    ? 'This date has no recorded reminder events.'
                    : 'Create one from the Reminders tab.',
              )
            else
              ...selectedEvents.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppSurfaceCard(
                    dense: true,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: cs.secondary.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            entry.isRepeating
                                ? Icons.repeat_rounded
                                : Icons.alarm_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('h:mm a').format(entry.when),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tone.mutedText),
                              ),
                              if ((entry.description ?? '').trim().isNotEmpty)
                                Text(
                                  entry.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: tone.mutedText),
                                ),
                            ],
                          ),
                        ),
                        if (entry.missed)
                          Icon(
                            Icons.warning_amber_rounded,
                            color: cs.error,
                            size: 18,
                          )
                        else if (entry.completed)
                          Icon(
                            Icons.check_circle_rounded,
                            color: tone.success,
                            size: 18,
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

  String _selectedTitle(DateTime selected, DateTime today) {
    if (_dayOnly(selected) == _dayOnly(today)) return 'Today';
    return DateFormat('MMMM d').format(selected);
  }
}

enum _DotStatus { all, some, none }

class _CalendarEntry {
  final String title;
  final String? description;
  final DateTime when;
  final bool isRepeating;
  final bool completed;
  final bool missed;

  const _CalendarEntry({
    required this.title,
    required this.when,
    required this.isRepeating,
    required this.completed,
    required this.missed,
    this.description,
  });
}

class _DayLabel extends StatelessWidget {
  final String text;

  const _DayLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTone.of(context).mutedText,
          ),
        ),
      ),
    );
  }
}
