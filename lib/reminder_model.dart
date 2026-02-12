import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum RepeatType { none, daily, weekly, interval }

RepeatType repeatTypeFromString(String? value) {
  switch (value) {
    case 'daily':
      return RepeatType.daily;
    case 'weekly':
      return RepeatType.weekly;
    case 'interval':
      return RepeatType.interval;
    default:
      return RepeatType.none;
  }
}

String? repeatTypeToString(RepeatType type) {
  switch (type) {
    case RepeatType.none:
      return null;
    case RepeatType.daily:
      return 'daily';
    case RepeatType.weekly:
      return 'weekly';
    case RepeatType.interval:
      return 'interval';
  }
}

enum ReminderAlertMode { notifyOnly, ringOnly, ringAndNotify }

ReminderAlertMode reminderAlertModeFromString(String? value) {
  switch (value) {
    case 'notify_only':
      return ReminderAlertMode.notifyOnly;
    case 'ring_only':
      return ReminderAlertMode.ringOnly;
    case 'ring_and_notify':
      return ReminderAlertMode.ringAndNotify;
    default:
      return ReminderAlertMode.ringAndNotify;
  }
}

String reminderAlertModeToString(ReminderAlertMode mode) {
  switch (mode) {
    case ReminderAlertMode.notifyOnly:
      return 'notify_only';
    case ReminderAlertMode.ringOnly:
      return 'ring_only';
    case ReminderAlertMode.ringAndNotify:
      return 'ring_and_notify';
  }
}

enum ReminderPriority { low, medium, high }

ReminderPriority reminderPriorityFromString(String? value) {
  switch (value) {
    case 'low':
      return ReminderPriority.low;
    case 'high':
      return ReminderPriority.high;
    case 'medium':
    default:
      return ReminderPriority.medium;
  }
}

String reminderPriorityToString(ReminderPriority priority) {
  switch (priority) {
    case ReminderPriority.low:
      return 'low';
    case ReminderPriority.medium:
      return 'medium';
    case ReminderPriority.high:
      return 'high';
  }
}

class ReminderRecurrence {
  final RepeatType type;
  final List<int> weekdays;
  final int? intervalDays;
  final List<int> timesOfDay;
  final DateTime? endAt;

  ReminderRecurrence({
    this.type = RepeatType.none,
    List<int>? weekdays,
    this.intervalDays,
    List<int>? timesOfDay,
    this.endAt,
  }) : weekdays = weekdays == null ? const [] : List.unmodifiable(weekdays),
       timesOfDay = timesOfDay == null
           ? const []
           : List.unmodifiable(timesOfDay);

  bool get isRepeating => type != RepeatType.none;

  bool get isAdvanced {
    if (type == RepeatType.interval) return true;
    if (timesOfDay.length > 1) return true;
    if (endAt != null) return true;
    if (type == RepeatType.weekly && weekdays.length > 1) return true;
    return false;
  }

  ReminderRecurrence copyWith({
    RepeatType? type,
    List<int>? weekdays,
    int? intervalDays,
    List<int>? timesOfDay,
    DateTime? endAt,
    bool clearEndAt = false,
  }) {
    return ReminderRecurrence(
      type: type ?? this.type,
      weekdays: weekdays ?? this.weekdays,
      intervalDays: intervalDays ?? this.intervalDays,
      timesOfDay: timesOfDay ?? this.timesOfDay,
      endAt: clearEndAt ? null : (endAt ?? this.endAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': repeatTypeToString(type),
      'weekdays': weekdays,
      'intervalDays': intervalDays,
      'timesOfDay': timesOfDay,
      'endAt': endAt?.toIso8601String(),
    };
  }

  factory ReminderRecurrence.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ReminderRecurrence();
    return ReminderRecurrence(
      type: repeatTypeFromString(json['type'] as String?),
      weekdays: _parseIntList(json['weekdays']),
      intervalDays: (json['intervalDays'] as num?)?.toInt(),
      timesOfDay: _parseIntList(json['timesOfDay']),
      endAt: _parseDate(json['endAt']),
    );
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'type': repeatTypeToString(type),
      'weekdays': weekdays,
      'intervalDays': intervalDays,
      'timesOfDay': timesOfDay,
      'endAt': endAt == null ? null : Timestamp.fromDate(endAt!),
    };
  }

  factory ReminderRecurrence.fromCloudMap(Map<String, dynamic>? json) {
    if (json == null) return ReminderRecurrence();
    return ReminderRecurrence(
      type: repeatTypeFromString(json['type'] as String?),
      weekdays: _parseIntList(json['weekdays']),
      intervalDays: (json['intervalDays'] as num?)?.toInt(),
      timesOfDay: _parseIntList(json['timesOfDay']),
      endAt: _parseDate(json['endAt']),
    );
  }
}

class ReminderModel {
  final String id;
  final String title;
  final String? description;
  final DateTime dueAt;
  final bool completed;
  final bool missed;
  final ReminderRecurrence recurrence;
  final ReminderAlertMode alertMode;
  final ReminderPriority priority;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastCompletedAt;
  final int missedCount;
  final int completionCount;
  final int totalOccurrences;
  final int consecutiveSnoozes;
  final int streakBeforeMiss;
  final int recoveryUsedCount;
  final DateTime? lastRecoveryAt;
  final int? suggestionMinutesOfDay;
  final String? suggestionMessage;
  final DateTime? suggestionCreatedAt;
  final DateTime? lastOccurrenceAt;
  final String? lastOccurrenceStatus;
  final int? notifIdMain;
  final int? notifIdPre;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReminderModel({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.completed = false,
    this.missed = false,
    ReminderRecurrence? recurrence,
    this.alertMode = ReminderAlertMode.ringAndNotify,
    this.priority = ReminderPriority.medium,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastCompletedAt,
    this.missedCount = 0,
    this.completionCount = 0,
    this.totalOccurrences = 0,
    this.consecutiveSnoozes = 0,
    this.streakBeforeMiss = 0,
    this.recoveryUsedCount = 0,
    this.lastRecoveryAt,
    this.suggestionMinutesOfDay,
    this.suggestionMessage,
    this.suggestionCreatedAt,
    this.lastOccurrenceAt,
    this.lastOccurrenceStatus,
    this.notifIdMain,
    this.notifIdPre,
  }) : recurrence = recurrence ?? ReminderRecurrence();

  bool get isActive => !completed && !missed;

  ReminderModel copyWith({
    String? id,
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? dueAt,
    bool? completed,
    bool? missed,
    ReminderRecurrence? recurrence,
    ReminderAlertMode? alertMode,
    ReminderPriority? priority,
    int? currentStreak,
    int? longestStreak,
    DateTime? lastCompletedAt,
    bool clearLastCompletedAt = false,
    int? missedCount,
    int? completionCount,
    int? totalOccurrences,
    int? consecutiveSnoozes,
    int? streakBeforeMiss,
    int? recoveryUsedCount,
    DateTime? lastRecoveryAt,
    bool clearLastRecoveryAt = false,
    int? suggestionMinutesOfDay,
    bool clearSuggestionMinutesOfDay = false,
    String? suggestionMessage,
    bool clearSuggestionMessage = false,
    DateTime? suggestionCreatedAt,
    bool clearSuggestionCreatedAt = false,
    DateTime? lastOccurrenceAt,
    bool clearLastOccurrenceAt = false,
    String? lastOccurrenceStatus,
    bool clearLastOccurrenceStatus = false,
    int? notifIdMain,
    bool clearNotifIdMain = false,
    int? notifIdPre,
    bool clearNotifIdPre = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReminderModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      dueAt: dueAt ?? this.dueAt,
      completed: completed ?? this.completed,
      missed: missed ?? this.missed,
      recurrence: recurrence ?? this.recurrence,
      alertMode: alertMode ?? this.alertMode,
      priority: priority ?? this.priority,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastCompletedAt: clearLastCompletedAt
          ? null
          : (lastCompletedAt ?? this.lastCompletedAt),
      missedCount: missedCount ?? this.missedCount,
      completionCount: completionCount ?? this.completionCount,
      totalOccurrences: totalOccurrences ?? this.totalOccurrences,
      consecutiveSnoozes: consecutiveSnoozes ?? this.consecutiveSnoozes,
      streakBeforeMiss: streakBeforeMiss ?? this.streakBeforeMiss,
      recoveryUsedCount: recoveryUsedCount ?? this.recoveryUsedCount,
      lastRecoveryAt: clearLastRecoveryAt
          ? null
          : (lastRecoveryAt ?? this.lastRecoveryAt),
      suggestionMinutesOfDay: clearSuggestionMinutesOfDay
          ? null
          : (suggestionMinutesOfDay ?? this.suggestionMinutesOfDay),
      suggestionMessage: clearSuggestionMessage
          ? null
          : (suggestionMessage ?? this.suggestionMessage),
      suggestionCreatedAt: clearSuggestionCreatedAt
          ? null
          : (suggestionCreatedAt ?? this.suggestionCreatedAt),
      lastOccurrenceAt: clearLastOccurrenceAt
          ? null
          : (lastOccurrenceAt ?? this.lastOccurrenceAt),
      lastOccurrenceStatus: clearLastOccurrenceStatus
          ? null
          : (lastOccurrenceStatus ?? this.lastOccurrenceStatus),
      notifIdMain: clearNotifIdMain ? null : (notifIdMain ?? this.notifIdMain),
      notifIdPre: clearNotifIdPre ? null : (notifIdPre ?? this.notifIdPre),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dueAt': dueAt.toIso8601String(),
      'completed': completed,
      'missed': missed,
      'recurrence': recurrence.toJson(),
      'alertMode': reminderAlertModeToString(alertMode),
      'priority': reminderPriorityToString(priority),
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastCompletedAt': lastCompletedAt?.toIso8601String(),
      'missedCount': missedCount,
      'completionCount': completionCount,
      'totalOccurrences': totalOccurrences,
      'consecutiveSnoozes': consecutiveSnoozes,
      'streakBeforeMiss': streakBeforeMiss,
      'recoveryUsedCount': recoveryUsedCount,
      'lastRecoveryAt': lastRecoveryAt?.toIso8601String(),
      'suggestionMinutesOfDay': suggestionMinutesOfDay,
      'suggestionMessage': suggestionMessage,
      'suggestionCreatedAt': suggestionCreatedAt?.toIso8601String(),
      'lastOccurrenceAt': lastOccurrenceAt?.toIso8601String(),
      'lastOccurrenceStatus': lastOccurrenceStatus,
      'notifIdMain': notifIdMain,
      'notifIdPre': notifIdPre,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'title': title,
      'description': description,
      'dueAt': Timestamp.fromDate(dueAt),
      'completed': completed,
      'missed': missed,
      'recurrence': recurrence.toCloudMap(),
      'alertMode': reminderAlertModeToString(alertMode),
      'priority': reminderPriorityToString(priority),
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastCompletedAt': _timestampOrNull(lastCompletedAt),
      'missedCount': missedCount,
      'completionCount': completionCount,
      'totalOccurrences': totalOccurrences,
      'consecutiveSnoozes': consecutiveSnoozes,
      'streakBeforeMiss': streakBeforeMiss,
      'recoveryUsedCount': recoveryUsedCount,
      'lastRecoveryAt': _timestampOrNull(lastRecoveryAt),
      'suggestionMinutesOfDay': suggestionMinutesOfDay,
      'suggestionMessage': suggestionMessage,
      'suggestionCreatedAt': _timestampOrNull(suggestionCreatedAt),
      'lastOccurrenceAt': _timestampOrNull(lastOccurrenceAt),
      'lastOccurrenceStatus': lastOccurrenceStatus,
      'notifIdMain': notifIdMain,
      'notifIdPre': notifIdPre,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ReminderModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description'] as String?,
      dueAt: _parseDate(json['dueAt']) ?? now,
      completed: (json['completed'] ?? false) == true,
      missed: (json['missed'] ?? false) == true,
      recurrence: ReminderRecurrence.fromJson(
        json['recurrence'] as Map<String, dynamic>?,
      ),
      alertMode: reminderAlertModeFromString(json['alertMode'] as String?),
      priority: reminderPriorityFromString(json['priority'] as String?),
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      lastCompletedAt: _parseDate(json['lastCompletedAt']),
      missedCount: (json['missedCount'] as num?)?.toInt() ?? 0,
      completionCount: (json['completionCount'] as num?)?.toInt() ?? 0,
      totalOccurrences: (json['totalOccurrences'] as num?)?.toInt() ?? 0,
      consecutiveSnoozes: (json['consecutiveSnoozes'] as num?)?.toInt() ?? 0,
      streakBeforeMiss: (json['streakBeforeMiss'] as num?)?.toInt() ?? 0,
      recoveryUsedCount: (json['recoveryUsedCount'] as num?)?.toInt() ?? 0,
      lastRecoveryAt: _parseDate(json['lastRecoveryAt']),
      suggestionMinutesOfDay: (json['suggestionMinutesOfDay'] as num?)?.toInt(),
      suggestionMessage: json['suggestionMessage'] as String?,
      suggestionCreatedAt: _parseDate(json['suggestionCreatedAt']),
      lastOccurrenceAt: _parseDate(json['lastOccurrenceAt']),
      lastOccurrenceStatus: json['lastOccurrenceStatus'] as String?,
      notifIdMain: (json['notifIdMain'] as num?)?.toInt(),
      notifIdPre: (json['notifIdPre'] as num?)?.toInt(),
      createdAt: _parseDate(json['createdAt']) ?? now,
      updatedAt: _parseDate(json['updatedAt']) ?? now,
    );
  }

  factory ReminderModel.fromCloudDoc(String id, Map<String, dynamic> data) {
    final now = DateTime.now();
    return ReminderModel(
      id: id,
      title: (data['title'] ?? '').toString(),
      description: data['description'] as String?,
      dueAt: _parseDate(data['dueAt']) ?? now,
      completed: (data['completed'] ?? false) == true,
      missed: (data['missed'] ?? false) == true,
      recurrence: ReminderRecurrence.fromCloudMap(
        data['recurrence'] as Map<String, dynamic>?,
      ),
      alertMode: reminderAlertModeFromString(data['alertMode'] as String?),
      priority: reminderPriorityFromString(data['priority'] as String?),
      currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (data['longestStreak'] as num?)?.toInt() ?? 0,
      lastCompletedAt: _parseDate(data['lastCompletedAt']),
      missedCount: (data['missedCount'] as num?)?.toInt() ?? 0,
      completionCount: (data['completionCount'] as num?)?.toInt() ?? 0,
      totalOccurrences: (data['totalOccurrences'] as num?)?.toInt() ?? 0,
      consecutiveSnoozes: (data['consecutiveSnoozes'] as num?)?.toInt() ?? 0,
      streakBeforeMiss: (data['streakBeforeMiss'] as num?)?.toInt() ?? 0,
      recoveryUsedCount: (data['recoveryUsedCount'] as num?)?.toInt() ?? 0,
      lastRecoveryAt: _parseDate(data['lastRecoveryAt']),
      suggestionMinutesOfDay: (data['suggestionMinutesOfDay'] as num?)?.toInt(),
      suggestionMessage: data['suggestionMessage'] as String?,
      suggestionCreatedAt: _parseDate(data['suggestionCreatedAt']),
      lastOccurrenceAt: _parseDate(data['lastOccurrenceAt']),
      lastOccurrenceStatus: data['lastOccurrenceStatus'] as String?,
      notifIdMain: (data['notifIdMain'] as num?)?.toInt(),
      notifIdPre: (data['notifIdPre'] as num?)?.toInt(),
      createdAt: _parseDate(data['createdAt']) ?? now,
      updatedAt: _parseDate(data['updatedAt']) ?? now,
    );
  }
}

enum ReminderEventType { completed, snoozed, missed }

ReminderEventType reminderEventTypeFromString(String? value) {
  switch (value) {
    case 'completed':
      return ReminderEventType.completed;
    case 'snoozed':
      return ReminderEventType.snoozed;
    case 'missed':
      return ReminderEventType.missed;
    default:
      return ReminderEventType.completed;
  }
}

String reminderEventTypeToString(ReminderEventType type) {
  switch (type) {
    case ReminderEventType.completed:
      return 'completed';
    case ReminderEventType.snoozed:
      return 'snoozed';
    case ReminderEventType.missed:
      return 'missed';
  }
}

class ReminderEvent {
  final String id;
  final String reminderId;
  final ReminderEventType type;
  final DateTime scheduledAt;
  final DateTime occurredAt;
  final int? snoozeMinutes;

  const ReminderEvent({
    required this.id,
    required this.reminderId,
    required this.type,
    required this.scheduledAt,
    required this.occurredAt,
    this.snoozeMinutes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reminderId': reminderId,
      'type': reminderEventTypeToString(type),
      'scheduledAt': scheduledAt.toIso8601String(),
      'occurredAt': occurredAt.toIso8601String(),
      'snoozeMinutes': snoozeMinutes,
    };
  }

  factory ReminderEvent.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ReminderEvent(
      id: (json['id'] ?? '').toString(),
      reminderId: (json['reminderId'] ?? '').toString(),
      type: reminderEventTypeFromString(json['type'] as String?),
      scheduledAt: _parseDate(json['scheduledAt']) ?? now,
      occurredAt: _parseDate(json['occurredAt']) ?? now,
      snoozeMinutes: (json['snoozeMinutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'reminderId': reminderId,
      'type': reminderEventTypeToString(type),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'occurredAt': Timestamp.fromDate(occurredAt),
      'snoozeMinutes': snoozeMinutes,
    };
  }

  factory ReminderEvent.fromCloudDoc(String id, Map<String, dynamic> data) {
    final now = DateTime.now();
    return ReminderEvent(
      id: id,
      reminderId: (data['reminderId'] ?? '').toString(),
      type: reminderEventTypeFromString(data['type'] as String?),
      scheduledAt: _parseDate(data['scheduledAt']) ?? now,
      occurredAt: _parseDate(data['occurredAt']) ?? now,
      snoozeMinutes: (data['snoozeMinutes'] as num?)?.toInt(),
    );
  }
}

Timestamp? _timestampOrNull(DateTime? dt) {
  if (dt == null) return null;
  return Timestamp.fromDate(dt);
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

List<int> _parseIntList(dynamic raw) {
  if (raw is Iterable) {
    final out = raw
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .toSet()
        .toList();
    out.sort();
    return out;
  }
  return const [];
}

int minutesOfDay(DateTime dt) => dt.hour * 60 + dt.minute;

DateTime dateWithMinutes(DateTime date, int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return DateTime(date.year, date.month, date.day, h, m);
}

String generateReminderId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(1 << 32);
  return 'r_${now}_$random';
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
