import 'package:audioplayers/audioplayers.dart';

import 'reminder_sounds.dart';

class AlarmPlayer {
  AlarmPlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _started = false;
  static String? _activeSoundId;

  static Future<void> start({String? alarmSoundId}) async {
    final sound = ReminderSounds.alarmById(alarmSoundId);
    if (_started && _activeSoundId == sound.id) return;

    _started = true;
    _activeSoundId = sound.id;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.stop();
    await _player.play(AssetSource(sound.assetSourcePath), volume: 1.0);
  }

  static Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _activeSoundId = null;
    await _player.stop();
  }
}
