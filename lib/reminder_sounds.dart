enum ReminderSoundType { alarm, notification }

class ReminderSoundOption {
  final String id;
  final String label;
  final String assetPath;
  final String androidRawResource;
  final ReminderSoundType type;

  const ReminderSoundOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.androidRawResource,
    required this.type,
  });

  String get assetSourcePath {
    if (assetPath.startsWith('assets/')) {
      return assetPath.substring('assets/'.length);
    }
    return assetPath;
  }
}

class ReminderSounds {
  ReminderSounds._();

  static const String defaultAlarmSoundId = 'alarm_classic';
  static const String defaultNotificationSoundId = 'notify_soft';

  static const List<ReminderSoundOption> alarmOptions = [
    ReminderSoundOption(
      id: 'alarm_classic',
      label: 'Classic Alarm',
      assetPath: 'assets/sounds/alarm_classic.wav',
      androidRawResource: 'alarm_classic',
      type: ReminderSoundType.alarm,
    ),
    ReminderSoundOption(
      id: 'alarm_bell',
      label: 'Bell Alarm',
      assetPath: 'assets/sounds/alarm_bell.wav',
      androidRawResource: 'alarm_bell',
      type: ReminderSoundType.alarm,
    ),
    ReminderSoundOption(
      id: 'alarm_urgent',
      label: 'Urgent Alarm',
      assetPath: 'assets/sounds/alarm_urgent.wav',
      androidRawResource: 'alarm_urgent',
      type: ReminderSoundType.alarm,
    ),
  ];

  static const List<ReminderSoundOption> notificationOptions = [
    ReminderSoundOption(
      id: 'notify_soft',
      label: 'Soft Notify',
      assetPath: 'assets/sounds/notify_soft.wav',
      androidRawResource: 'notify_soft',
      type: ReminderSoundType.notification,
    ),
    ReminderSoundOption(
      id: 'notify_ping',
      label: 'Ping Notify',
      assetPath: 'assets/sounds/notify_ping.wav',
      androidRawResource: 'notify_ping',
      type: ReminderSoundType.notification,
    ),
    ReminderSoundOption(
      id: 'notify_pop',
      label: 'Pop Notify',
      assetPath: 'assets/sounds/notify_pop.wav',
      androidRawResource: 'notify_pop',
      type: ReminderSoundType.notification,
    ),
  ];

  static ReminderSoundOption alarmById(String? id) {
    return alarmOptions.firstWhere(
      (sound) => sound.id == id,
      orElse: () => alarmOptions.first,
    );
  }

  static ReminderSoundOption notificationById(String? id) {
    return notificationOptions.firstWhere(
      (sound) => sound.id == id,
      orElse: () => notificationOptions.first,
    );
  }
}
