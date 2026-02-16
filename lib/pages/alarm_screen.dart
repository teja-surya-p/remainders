import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alarm_player.dart';
import '../alarm_vibration.dart';
import '../app_services.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';

class AlarmScreen extends StatefulWidget {
  final String reminderId;

  const AlarmScreen({super.key, required this.reminderId});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {
  final TextEditingController _customMinutes = TextEditingController();
  DateTime? _exactSnoozeAt;
  bool _processing = false;
  bool _showCustom = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void initState() {
    super.initState();
    _startAlarmMedia();

    Future<void>.delayed(const Duration(seconds: 1), () async {
      while (mounted) {
        await _shake.forward();
        await _shake.reverse();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    });
  }

  Future<void> _startAlarmMedia() async {
    String? alarmSoundId;
    try {
      final reminder = await AppServices.reminders.getReminder(
        widget.reminderId,
      );
      alarmSoundId = reminder?.alarmSoundId;
    } catch (_) {}
    await AlarmPlayer.start(alarmSoundId: alarmSoundId);
    await AlarmVibration.start();
  }

  Future<void> _stop() async {
    if (_processing) return;
    setState(() => _processing = true);
    await AppServices.reminders.completeReminder(widget.reminderId);
    await AlarmPlayer.stop();
    await AlarmVibration.stop();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickExactDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _exactSnoozeAt ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _exactSnoozeAt ?? now.add(const Duration(minutes: 5)),
      ),
    );
    if (time == null) return;

    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!chosen.isAfter(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future date and time.')),
      );
      return;
    }

    setState(() => _exactSnoozeAt = chosen);
  }

  Future<void> _snoozeBy(Duration d) async {
    final newDueAt = DateTime.now().add(d);
    await _applySnooze(newDueAt);
  }

  Future<void> _snoozeCustomMinutes() async {
    final m = int.tryParse(_customMinutes.text.trim());
    if (m == null || m <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid custom minutes.')),
      );
      return;
    }
    await _snoozeBy(Duration(minutes: m));
  }

  Future<void> _snoozeExact() async {
    final exact = _exactSnoozeAt;
    if (exact == null) return;
    await _applySnooze(exact);
  }

  Future<void> _applySnooze(DateTime dueAt) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await AppServices.reminders.snoozeReminder(widget.reminderId, dueAt);
      await AlarmPlayer.stop();
      await AlarmVibration.stop();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to snooze: $e')));
    }
  }

  @override
  void dispose() {
    _customMinutes.dispose();
    _pulse.dispose();
    _shake.dispose();
    AlarmPlayer.stop();
    AlarmVibration.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.error.withValues(alpha: 0.22),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: StreamBuilder<List<ReminderModel>>(
              stream: AppServices.reminders.watchReminders(),
              builder: (context, snapshot) {
                final reminder = snapshot.data
                    ?.where((r) => r.id == widget.reminderId)
                    .firstOrNull;
                final title = reminder?.title ?? 'Reminder';
                final snoozeCount = reminder?.consecutiveSnoozes ?? 0;
                final exactLabel = _exactSnoozeAt == null
                    ? 'Pick exact date & time'
                    : DateFormat('EEE, MMM d • h:mm a').format(_exactSnoozeAt!);

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    children: [
                      Center(
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, child) {
                                  final t = _pulse.value;
                                  return CustomPaint(
                                    painter: _PulsePainter(
                                      progress: t,
                                      color: cs.primary,
                                    ),
                                    child: const SizedBox.expand(),
                                  );
                                },
                              ),
                              AnimatedBuilder(
                                animation: _shake,
                                builder: (context, child) {
                                  final angle =
                                      math.sin(_shake.value * math.pi * 8) *
                                      0.06;
                                  return Transform.rotate(
                                    angle: angle,
                                    child: Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: cs.primary.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 22,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.alarm_rounded,
                                        color: cs.onPrimary,
                                        size: 42,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if ((reminder?.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          reminder!.description!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: tone.mutedText),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.secondary.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            DateFormat(
                              'h:mm a',
                            ).format(reminder?.dueAt ?? DateTime.now()),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                      if (snoozeCount > 0) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: tone.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'Snoozed $snoozeCount times',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: tone.warning,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'Snooze for',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: tone.mutedText),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              label: '5 min',
                              onTap: _processing
                                  ? null
                                  : () => _snoozeBy(const Duration(minutes: 5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionButton(
                              label: '10 min',
                              onTap: _processing
                                  ? null
                                  : () =>
                                        _snoozeBy(const Duration(minutes: 10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              label: '30 min',
                              onTap: _processing
                                  ? null
                                  : () =>
                                        _snoozeBy(const Duration(minutes: 30)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionButton(
                              label: _showCustom ? 'Hide custom' : 'Custom',
                              onTap: _processing
                                  ? null
                                  : () => setState(
                                      () => _showCustom = !_showCustom,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: AppMotion.card,
                        curve: AppMotion.standard,
                        child: !_showCustom
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _customMinutes,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          hintText: 'Custom minutes',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _processing
                                          ? null
                                          : _snoozeCustomMinutes,
                                      child: const Text('Snooze'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      _ActionButton(
                        label: exactLabel,
                        icon: Icons.event_rounded,
                        onTap: _processing ? null : _pickExactDateTime,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _processing || _exactSnoozeAt == null
                            ? null
                            : _snoozeExact,
                        child: const Text('Snooze to selected date & time'),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _processing ? null : _stop,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Dismiss Alarm'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  const _ActionButton({required this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      dense: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rings = [0.0, 0.33, 0.66];
    for (final shift in rings) {
      final t = ((progress + shift) % 1);
      final radius = 40 + (t * 62);
      final opacity = (1 - t).clamp(0.0, 1.0) * 0.22;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
