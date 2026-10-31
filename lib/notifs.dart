import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone_updated_gradle/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_sounds.dart';

enum AlarmPriorityLevel { low, medium, high }

class Notifs {
  Notifs._();

  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();
  static bool _canScheduleExact = true;
  static bool _notificationsEnabled = true;
  static final Set<String> _createdChannelIds = <String>{};

  // Track which OS permission prompts we have already shown the user this
  // session so we don't bounce them through multiple Settings pages back to
  // back (especially the exact-alarm + full-screen-intent prompts which are
  // separate Settings activities, not in-app dialogs).
  static bool _exactAlarmPrompted = false;
  static bool _fullScreenIntentPrompted = false;

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
    tzdata.initializeTimeZones();
    await _configureTimezone();

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

    // Use a monochrome alpha-only drawable for the status-bar small icon.
    // The system renders @mipmap/ic_launcher (a colored bitmap) as a featureless
    // grey square because it ignores all channels except alpha for the small
    // icon position.
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
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      final android = _p
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Only ask for the POST_NOTIFICATIONS runtime permission on init — it's
      // an in-app dialog. Defer SCHEDULE_EXACT_ALARM and USE_FULL_SCREEN_INTENT
      // (each opens a separate Settings page) until the user actually creates
      // an alarm reminder, so we never bounce them through three system
      // screens during first launch.
      await _refreshAndroidPermissionState(
        android,
        requestNotif: true,
        requestExactAlarm: false,
        requestFullScreenIntent: false,
      );
      await _createAndroidChannels(android);
    }
  }

  static Future<void> _configureTimezone() async {
    try {
      final nativeName = await FlutterNativeTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 3),
      );
      try {
        tz.setLocalLocation(tz.getLocation(nativeName));
        return;
      } catch (_) {
        // Native name was not in the IANA database — fall through to the
        // offset-based fallback below.
      }
    } catch (_) {
      // Plugin call failed (e.g. platform channel error) — fall through.
    }

    // Best-effort fallback: derive a fixed-offset zone from the system clock
    // so absolute scheduling stays correct even when the IANA name lookup
    // fails. Etc/GMT zones use POSIX-inverted signs (Etc/GMT+5 is UTC-5h).
    try {
      final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final hours = offsetMinutes ~/ 60;
      if (hours == 0) {
        tz.setLocalLocation(tz.getLocation('UTC'));
        return;
      }
      final etcName = hours > 0 ? 'Etc/GMT-$hours' : 'Etc/GMT+${-hours}';
      tz.setLocalLocation(tz.getLocation(etcName));
      return;
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
  }) async {
    AndroidFlutterLocalNotificationsPlugin? androidPlatform;
    if (Platform.isAndroid) {
      final android = _p
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      androidPlatform = android;
      await _refreshAndroidPermissionState(
        android,
        requestNotif: false,
        requestExactAlarm: false,
        requestFullScreenIntent: false,
      );
      if (android != null) {
        // Lazily prompt for the OS-level permissions we actually need for this
        // particular schedule, but only once per session per permission so we
        // don't open the same Settings page repeatedly.
        final needNotif = !_notificationsEnabled;
        final needExact = isAlarm && !_canScheduleExact && !_exactAlarmPrompted;
        final needFsi = isAlarm && !_fullScreenIntentPrompted;
        if (needNotif || needExact || needFsi) {
          await _refreshAndroidPermissionState(
            android,
            requestNotif: needNotif,
            requestExactAlarm: needExact,
            requestFullScreenIntent: needFsi,
          );
          if (needExact) _exactAlarmPrompted = true;
          if (needFsi) _fullScreenIntentPrompted = true;
        }
      }
      if (!_notificationsEnabled) {
        debugPrint(
          'Notifications are disabled at OS level. Alarm notification may not appear.',
        );
      }
      if (isAlarm && !_canScheduleExact) {
        debugPrint(
          'Exact alarm permission is not granted. Using inexact scheduling fallback.',
        );
      }
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
      actions: enableActions
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(aSnooze5, '5m'),
              const AndroidNotificationAction(aSnooze10, '10m'),
              const AndroidNotificationAction(aSnooze30, '30m'),
              // Inline RemoteInput lets the user type a custom snooze duration
              // (minutes) directly from the notification, even when the app is
              // killed. Without inputs, the background isolate has no way to
              // know what duration to apply and the action would silently
              // do nothing. `showsUserInterface: true` is the fallback for
              // taps without input — it brings the app to the foreground so
              // SnoozeScreen can collect the value.
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

    try {
      await _zonedSchedule(
        id: id,
        title: title,
        body: body,
        whenLocal: whenLocal,
        details: NotificationDetails(android: android, iOS: ios),
        androidScheduleMode: androidScheduleMode,
        payload: payload,
      );
    } catch (e) {
      if (Platform.isAndroid &&
          androidScheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        debugPrint(
          'Primary schedule failed for notification $id. Retrying with inexact mode. Error: $e',
        );
        await _zonedSchedule(
          id: id,
          title: title,
          body: body,
          whenLocal: whenLocal,
          details: NotificationDetails(android: android, iOS: ios),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        return;
      }
      rethrow;
    }
  }

  static Future<void> cancel(int id) => _p.cancel(id: id);

  static AndroidScheduleMode _resolveScheduleMode({required bool isAlarm}) {
    if (isAlarm) {
      if (!_canScheduleExact) {
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
      return AndroidScheduleMode.alarmClock;
    }
    if (!_canScheduleExact) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    return AndroidScheduleMode.exactAllowWhileIdle;
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

  static String _priorityLabel(AlarmPriorityLevel level) {
    switch (level) {
      case AlarmPriorityLevel.low:
        return 'Low';
      case AlarmPriorityLevel.medium:
        return 'Medium';
      case AlarmPriorityLevel.high:
        return 'High';
    }
  }

  static Future<void> _ensureAndroidChannel(
    AndroidFlutterLocalNotificationsPlugin? android,
    _ChannelConfig channel,
  ) async {
    if (android == null) return;
    if (_createdChannelIds.contains(channel.id)) return;
    try {
      await android.createNotificationChannel(channel.toAndroidChannel());
      _createdChannelIds.add(channel.id);
    } catch (_) {}
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
    final scheduledAt = tz.TZDateTime.from(whenLocal, tz.local);
    await _p.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledAt,
      notificationDetails: details,
      androidScheduleMode: androidScheduleMode,
      payload: payload,
    );
  }

  static Future<void> _refreshAndroidPermissionState(
    AndroidFlutterLocalNotificationsPlugin? android, {
    required bool requestNotif,
    required bool requestExactAlarm,
    required bool requestFullScreenIntent,
  }) async {
    if (android == null) return;

    if (requestNotif) {
      try {
        await android.requestNotificationsPermission();
      } catch (_) {}
    }
    if (requestExactAlarm) {
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {}
    }
    if (requestFullScreenIntent) {
      try {
        await android.requestFullScreenIntentPermission();
      } catch (_) {}
    }

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
  }

  static Future<void> _createAndroidChannels(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    await _ensureAndroidChannel(android, _silentConfig);
    await _ensureAndroidChannel(
      android,
      _resolveChannelConfig(
        isAlarm: true,
        playSound: true,
        priorityLevel: AlarmPriorityLevel.low,
        alarmSoundId: ReminderSounds.defaultAlarmSoundId,
      ),
    );
    await _ensureAndroidChannel(
      android,
      _resolveChannelConfig(
        isAlarm: true,
        playSound: true,
        priorityLevel: AlarmPriorityLevel.medium,
        alarmSoundId: ReminderSounds.defaultAlarmSoundId,
      ),
    );
    await _ensureAndroidChannel(
      android,
      _resolveChannelConfig(
        isAlarm: true,
        playSound: true,
        priorityLevel: AlarmPriorityLevel.high,
        alarmSoundId: ReminderSounds.defaultAlarmSoundId,
      ),
    );
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
