import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Times in the phone's own format: 12-hour ("9:50 AM") or 24-hour ("09:50")
/// as set in Android's date & time settings.
String formatTime(BuildContext context, DateTime time) =>
    formatTimeOfDay(context, TimeOfDay.fromDateTime(time));

String formatMinuteOfDay(BuildContext context, int minute) => formatTimeOfDay(
  context,
  TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60),
);

String formatTimeOfDay(BuildContext context, TimeOfDay time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "Mon, Nov 2 • 9:50 AM"
String formatDayAndTime(BuildContext context, DateTime time) =>
    '${DateFormat('EEE, MMM d').format(time)} • ${formatTime(context, time)}';
