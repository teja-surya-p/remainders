import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_sounds.dart';
import 'scheduling/alert_payload.dart';

enum AlarmPriorityLevel { low, medium, high }

/// What the OS currently allows. Anything that cannot be determined is
/// reported as not allowed, so the reliability check never over-promises.
class NotificationPermissions {
  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;

  const NotificationPermissions({
    required this.notificationsEnabled,
    required this.exactAlarmsAllowed,
  });

  bool get allGranted => notificationsEnabled && exactAlarmsAllowed;
}

/// A notification the OS has scheduled but not shown yet.
class PendingAlert {
  final int id;
  final AlertPayload? payload;

  const PendingAlert(this.id, this.payload);
}

class Notifs {
  Notifs._();

  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();
  static bool _canScheduleExact = true;
  static bool _notificationsEnabled = true;
  static bool _tzReady = false;
  static final Set<String> _createdChannelIds = <String>{};

  /// android.app.Notification.FLAG_INSISTENT: repeat the sound until the
  /// notification is answered or removed.
  static const int _flagInsistent = 4;

  static const String categoryId = 'REMINDER_CATEGORY';
  static const String _alarmLowChannelBase = 'reminders_alarm_low_v3';
  static const String _alarmMediumChannelBase = 'reminders_alarm_medium_v3';
  static const String _alarmHighChannelBase = 'reminders_alarm_high_v3';
  static const String _notifyChannelBase = 'reminders_notify_v3';
  static const String _silentChannelId = 'reminders_silent_v3';

  static const String aSnooze5 = 'SNOOZE_5';
  static const String aSnooze10 = 'SNOOZE_10';
  static const String aSnooze30 = 'SNOOZE_30';
  static const String aCustom = 'SNOOZE_CUSTOM';
  static const String aDismiss = 'DISMISS';

  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  static NotificationResponse? _pendingLaunchResponse;

  static final _ChannelConfig _silentConfig = _ChannelConfig(
    id: _silentChannelId,
    name: 'Reminders (Silent)',
    description: 'Silent reminder notifications',
    importance: Importance.high,
    priority: Priority.high,
    audioUsage: AudioAttributesUsage.notification,
    enableVibration: false,
  );

  static Future<void> init({
    DidReceiveNotificationResponseCallback? onAction,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundAction,
  }) async {
    await ensureTimeZone();

    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          categoryId,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(aSnooze5, 'Snooze 5m'),
            DarwinNotificationAction.plain(aSnooze10, 'Snooze 10m'),
            DarwinNotificationAction.plain(aSnooze30, 'Snooze 30m'),
            DarwinNotificationAction.text(
              aCustom,
              'Custom',
              buttonTitle: 'Set',
              placeholder: 'e.g. 15 or 09:30',
            ),
            DarwinNotificationAction.plain(
              aDismiss,
              'Dismiss',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
              },
            ),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );

    // Monochrome alpha-only drawable for the status-bar icon; a colored
    // launcher icon renders as a grey square there.
    const androidInit = AndroidInitializationSettings('ic_stat_notification');

    await _p.initialize(
      settings: InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: onAction,
      onDidReceiveBackgroundNotificationResponse: onBackgroundAction,
    );

    final launchDetails = await _p.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingLaunchResponse = launchDetails?.notificationResponse;
    }

    if (Platform.isIOS) {
      try {
        await _p
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (e) {
        debugPrint('iOS notification permission request failed: $e');
      }
    }

    if (Platform.isAndroid) {
      final android = _android();
      // Only the POST_NOTIFICATIONS dialog appears on first launch. Exact
      // alarms and full-screen alerts open separate Settings pages, so they
      // are requested from the UI (requestAlarmPermissions), never while the
      // scheduler is re-arming in the background.
      try {
        await android?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('Notification permission request failed: $e');
      }
      await _refreshAndroidPermissionState(android);
      await _createAndroidChannels(android);
    }
  }

  /// Loads the time-zone database and sets the device zone. Safe to call from
  /// any isolate, any number of times; every scheduling path calls it, so the
  /// notification-action background isolate can schedule too.
  static Future<void> ensureTimeZone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    await _configureTimezone();
    _tzReady = true;
  }

  /// Re-reads the device zone (after travel or a manual zone change).
  static Future<void> refreshTimeZone() async {
    _tzReady = false;
    await ensureTimeZone();
  }

  static Future<void> _configureTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 3),
      );
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return;
    } catch (e) {
      debugPrint('Device time zone lookup failed, using offset fallback: $e');
    }

    // Fallback: a fixed-offset zone from the system clock keeps absolute
    // scheduling correct when the IANA name is unavailable. Etc/GMT zones use
    // POSIX-inverted signs (Etc/GMT+5 is UTC-5h).
    try {
      final hours = DateTime.now().timeZoneOffset.inMinutes ~/ 60;
      final name = hours == 0
          ? 'UTC'
          : (hours > 0 ? 'Etc/GMT-$hours' : 'Etc/GMT+${-hours}');
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static NotificationResponse? takePendingLaunchResponse() {
    final r = _pendingLaunchResponse;
    _pendingLaunchResponse = null;
    return r;
  }

  static Future<void> schedule({
    required int id,
    required String title,
    String? body,
    required DateTime whenLocal,
    String? payload,
    bool isAlarm = false,
    bool playSound = true,
    String? alarmSoundId,
    String? notificationSoundId,
    bool enableVibration = true,
    bool enableActions = true,
    AlarmPriorityLevel priorityLevel = AlarmPriorityLevel.medium,
    Duration? timeoutAfter,
  }) async {
    await ensureTimeZone();

    AndroidFlutterLocalNotificationsPlugin? androidPlatform;
    if (Platform.isAndroid) {
      androidPlatform = _android();
      await _refreshAndroidPermissionState(androidPlatform);
    }

    final androidScheduleMode = _resolveScheduleMode(isAlarm: isAlarm);
    final channel = _resolveChannelConfig(
      isAlarm: isAlarm,
      playSound: playSound,
      priorityLevel: priorityLevel,
      alarmSoundId: alarmSoundId,
      notificationSoundId: notificationSoundId,
    );
    if (Platform.isAndroid) {
      await _ensureAndroidChannel(androidPlatform, channel);
    }

    final android = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      playSound: playSound,
      sound: playSound && channel.soundResource != null
          ? RawResourceAndroidNotificationSound(channel.soundResource!)
          : null,
      enableVibration: enableVibration,
      vibrationPattern: enableVibration
          ? Int64List.fromList([0, 1000, 500, 1000])
          : null,
      category: isAlarm ? AndroidNotificationCategory.alarm : null,
      fullScreenIntent: isAlarm,
      audioAttributesUsage: channel.audioUsage,
      // Alarms ring until answered: the sound repeats, the notification can't
      // be swiped away, and it disappears on its own after [timeoutAfter].
      ongoing: isAlarm,
      autoCancel: !isAlarm,
      additionalFlags: isAlarm ? Int32List.fromList([_flagInsistent]) : null,
      timeoutAfter: timeoutAfter?.inMilliseconds,
      visibility: isAlarm ? NotificationVisibility.public : null,
      actions: enableActions
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(aSnooze5, '5m'),
              const AndroidNotificationAction(aSnooze10, '10m'),
              const AndroidNotificationAction(aSnooze30, '30m'),
              // Inline RemoteInput lets the user type a custom snooze even
              // when the app is closed; tapping without input opens the app.
              const AndroidNotificationAction(
                aCustom,
                'Custom',
                showsUserInterface: true,
                inputs: <AndroidNotificationActionInput>[
                  AndroidNotificationActionInput(
                    label: 'Minutes (e.g. 15)',
                    allowFreeFormInput: true,
                  ),
                ],
              ),
              const AndroidNotificationAction(aDismiss, 'Dismiss'),
            ]
          : const <AndroidNotificationAction>[],
    );

    final ios = DarwinNotificationDetails(
      presentSound: playSound,
      sound: playSound ? 'default' : null,
      categoryIdentifier: enableActions ? categoryId : null,
    );

    final details = NotificationDetails(android: android, iOS: ios);
    try {
      await _zonedSchedule(
        id: id,
        title: title,
        body: body,
        whenLocal: whenLocal,
        details: details,
        androidScheduleMode: androidScheduleMode,
        payload: payload,
      );
    } catch (e) {
      if (Platform.isAndroid &&
          androidScheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        debugPrint('Exact schedule failed for $id, retrying inexact: $e');
        await _zonedSchedule(
          id: id,
          title: title,
          body: body,
          whenLocal: whenLocal,
          details: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        return;
      }
      rethrow;
    }
  }

  static Future<void> cancel(int id) => _p.cancel(id: id);

  static Future<void> cancelAll() => _p.cancelAll();

  /// Everything scheduled but not yet shown.
  static Future<List<PendingAlert>> pendingAlerts() async {
    final requests = await _p.pendingNotificationRequests();
    return [
      for (final r in requests)
        PendingAlert(r.id, AlertPayload.decode(r.payload)),
    ];
  }

  /// IDs of notifications currently on screen (e.g. an alarm still ringing).
  static Future<Set<int>> activeIds() async {
    final active = await _p.getActiveNotifications();
    return {
      for (final n in active)
        if (n.id != null) n.id!,
    };
  }

  /// Fresh permission state, for the reliability check and setup screens.
  static Future<NotificationPermissions> permissions() async {
    if (!Platform.isAndroid) {
      return const NotificationPermissions(
        notificationsEnabled: true,
        exactAlarmsAllowed: true,
      );
    }
    final android = _android();
    var notificationsEnabled = false;
    var exactAllowed = false;
    try {
      notificationsEnabled = await android?.areNotificationsEnabled() ?? false;
    } catch (e) {
      debugPrint('areNotificationsEnabled failed: $e');
    }
    try {
      // null means the check doesn't apply (Android < 12): exact is allowed.
      exactAllowed = await android?.canScheduleExactNotifications() ?? true;
    } catch (e) {
      debugPrint('canScheduleExactNotifications failed: $e');
    }
    return NotificationPermissions(
      notificationsEnabled: notificationsEnabled,
      exactAlarmsAllowed: exactAllowed,
    );
  }

  /// Asks for what alarms need. Call from the UI (it opens Settings pages
  /// for exact alarms and full-screen alerts), never from background work.
  static Future<NotificationPermissions> requestAlarmPermissions() async {
    if (Platform.isAndroid) {
      final android = _android();
      final current = await permissions();
      try {
        if (!current.notificationsEnabled) {
          await android?.requestNotificationsPermission();
        }
        if (!current.exactAlarmsAllowed) {
          await android?.requestExactAlarmsPermission();
        }
        await android?.requestFullScreenIntentPermission();
      } catch (e) {
        debugPrint('Alarm permission request failed: $e');
      }
      await _refreshAndroidPermissionState(android);
    }
    return permissions();
  }

  static AndroidFlutterLocalNotificationsPlugin? _android() => _p
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static AndroidScheduleMode _resolveScheduleMode({required bool isAlarm}) {
    if (!_canScheduleExact) return AndroidScheduleMode.inexactAllowWhileIdle;
    return isAlarm
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.exactAllowWhileIdle;
  }

  static _ChannelConfig _resolveChannelConfig({
    required bool isAlarm,
    required bool playSound,
    required AlarmPriorityLevel priorityLevel,
    String? alarmSoundId,
    String? notificationSoundId,
  }) {
    if (!playSound) {
      return _silentConfig;
    }
    if (!isAlarm) {
      final sound = ReminderSounds.notificationById(notificationSoundId);
      return _ChannelConfig(
        id: '${_notifyChannelBase}_${sound.androidRawResource}',
        name: 'Reminders (${sound.label})',
        description: 'Reminder notifications with selected sound',
        importance: Importance.high,
        priority: Priority.high,
        audioUsage: AudioAttributesUsage.notification,
        soundResource: sound.androidRawResource,
      );
    }

    final sound = ReminderSounds.alarmById(alarmSoundId);
    final channelBase = switch (priorityLevel) {
      AlarmPriorityLevel.low => _alarmLowChannelBase,
      AlarmPriorityLevel.medium => _alarmMediumChannelBase,
      AlarmPriorityLevel.high => _alarmHighChannelBase,
    };
    final (importance, priority) = switch (priorityLevel) {
      AlarmPriorityLevel.low => (
        Importance.defaultImportance,
        Priority.defaultPriority,
      ),
      AlarmPriorityLevel.medium => (Importance.high, Priority.high),
      AlarmPriorityLevel.high => (Importance.max, Priority.max),
    };

    return _ChannelConfig(
      id: '${channelBase}_${sound.androidRawResource}',
      name: 'Reminders (${_priorityLabel(priorityLevel)} • ${sound.label})',
      description: 'Reminder alarms with selected sound',
      importance: importance,
      priority: priority,
      audioUsage: AudioAttributesUsage.alarm,
      soundResource: sound.androidRawResource,
    );
  }

  static String _priorityLabel(AlarmPriorityLevel level) => switch (level) {
    AlarmPriorityLevel.low => 'Low',
    AlarmPriorityLevel.medium => 'Medium',
    AlarmPriorityLevel.high => 'High',
  };

  static Future<void> _ensureAndroidChannel(
    AndroidFlutterLocalNotificationsPlugin? android,
    _ChannelConfig channel,
  ) async {
    if (android == null) return;
    if (_createdChannelIds.contains(channel.id)) return;
    try {
      await android.createNotificationChannel(channel.toAndroidChannel());
      _createdChannelIds.add(channel.id);
    } catch (e) {
      debugPrint('Creating notification channel ${channel.id} failed: $e');
    }
  }

  static Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String? body,
    required DateTime whenLocal,
    required NotificationDetails details,
    required AndroidScheduleMode androidScheduleMode,
    required String? payload,
  }) async {
    await ensureTimeZone();
    await _p.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(whenLocal, tz.local),
      notificationDetails: details,
      androidScheduleMode: androidScheduleMode,
      payload: payload,
    );
  }

  /// Caches what scheduling needs to pick a mode. Unknown values stay
  /// permissive here because a failed exact schedule falls back to inexact;
  /// [permissions] reports them honestly instead.
  static Future<void> _refreshAndroidPermissionState(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    try {
      _notificationsEnabled = await android.areNotificationsEnabled() ?? true;
    } catch (_) {
      _notificationsEnabled = true;
    }
    try {
      _canScheduleExact = await android.canScheduleExactNotifications() ?? true;
    } catch (_) {
      _canScheduleExact = true;
    }
    if (!_notificationsEnabled) {
      debugPrint('Notifications are disabled at OS level.');
    }
  }

  static Future<void> _createAndroidChannels(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    await _ensureAndroidChannel(android, _silentConfig);
    for (final level in AlarmPriorityLevel.values) {
      await _ensureAndroidChannel(
        android,
        _resolveChannelConfig(
          isAlarm: true,
          playSound: true,
          priorityLevel: level,
          alarmSoundId: ReminderSounds.defaultAlarmSoundId,
        ),
      );
    }
    await _ensureAndroidChannel(
      android,
      _resolveChannelConfig(
        isAlarm: false,
        playSound: true,
        priorityLevel: AlarmPriorityLevel.medium,
        notificationSoundId: ReminderSounds.defaultNotificationSoundId,
      ),
    );
  }
}

class _ChannelConfig {
  final String id;
  final String name;
  final String description;
  final Importance importance;
  final Priority priority;
  final AudioAttributesUsage audioUsage;
  final String? soundResource;
  final bool enableVibration;

  _ChannelConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
    required this.priority,
    required this.audioUsage,
    this.soundResource,
    this.enableVibration = true,
  });

  AndroidNotificationChannel toAndroidChannel() {
    return AndroidNotificationChannel(
      id,
      name,
      description: description,
      importance: importance,
      playSound: soundResource != null,
      sound: soundResource == null
          ? null
          : RawResourceAndroidNotificationSound(soundResource!),
      enableVibration: enableVibration,
      audioAttributesUsage: audioUsage,
    );
  }
}
