import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone_updated_gradle/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Notifs {
  Notifs._();

  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'reminders';
  static const String channelName = 'Reminders';
  static const String categoryId = 'REMINDER_CATEGORY';

  static const String aSnooze5 = 'SNOOZE_5';
  static const String aSnooze10 = 'SNOOZE_10';
  static const String aSnooze30 = 'SNOOZE_30';
  static const String aCustom = 'SNOOZE_CUSTOM';
  static const String aDismiss = 'DISMISS';

  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  static NotificationResponse? _pendingLaunchResponse;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    channelId,
    channelName,
    description: 'Reminder alerts',
    importance: Importance.max,
    playSound: true,
  );

  static Future<void> init({
    DidReceiveNotificationResponseCallback? onAction,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundAction,
  }) async {
    tzdata.initializeTimeZones();
    final name = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));

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
      await _p
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (Platform.isAndroid) {
      await _p
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _p
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
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
  }) async {
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Reminder alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      category: isAlarm ? AndroidNotificationCategory.alarm : null,
      fullScreenIntent: isAlarm,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(aSnooze5, '5m'),
        AndroidNotificationAction(aSnooze10, '10m'),
        AndroidNotificationAction(aSnooze30, '30m'),
        AndroidNotificationAction(aCustom, 'Custom', showsUserInterface: true),
        AndroidNotificationAction(aDismiss, 'Dismiss'),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentSound: true,
      sound: 'default',
      categoryIdentifier: categoryId,
    );

    await _p.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(whenLocal, tz.local),
      notificationDetails: NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> cancel(int id) => _p.cancel(id: id);
}
