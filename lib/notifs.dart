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

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

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
      await _refreshAndroidPermissionState(android, request: true);
      await _createAndroidChannels(android);
    }
  }

  static Future<void> _configureTimezone() async {
    try {
      final name = await FlutterNativeTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 3),
      );
      try {
        tz.setLocalLocation(tz.getLocation(name));
        return;
      } catch (_) {}
    } catch (_) {}

    // Fallback prevents startup failures when timezone plugin is unavailable.
    tz.setLocalLocation(tz.getLocation('UTC'));
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
      await _refreshAndroidPermissionState(android, request: false);
      if ((!_notificationsEnabled || (isAlarm && !_canScheduleExact)) &&
          android != null) {
        await _refreshAndroidPermissionState(android, request: true);
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
          ? const <AndroidNotificationAction>[
              AndroidNotificationAction(aSnooze5, '5m'),
              AndroidNotificationAction(aSnooze10, '10m'),
              AndroidNotificationAction(aSnooze30, '30m'),
              AndroidNotificationAction(
                aCustom,
                'Custom',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(aDismiss, 'Dismiss'),
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

  static Future<void> _refreshAndroidPermissionState(
    AndroidFlutterLocalNotificationsPlugin? android, {
    required bool request,
  }) async {
    if (android == null) return;

    if (request) {
      try {
        await android.requestNotificationsPermission();
      } catch (_) {}
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {}
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
