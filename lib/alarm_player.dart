import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'reminder_sounds.dart';

class AlarmPlayer {
  AlarmPlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _started = false;
  static String? _activeSoundId;

  /// Starts the looping alarm sound. Returns true once playback is actually
  /// running, false if it did not start within a few seconds — callers keep
  /// the notification ringing in that case, so an alarm is never silent.
  static Future<bool> start({String? alarmSoundId}) async {
    final sound = ReminderSounds.alarmById(alarmSoundId);
    if (_started && _activeSoundId == sound.id) {
      return _player.state == PlayerState.playing;
    }

    _started = true;
    _activeSoundId = sound.id;
    // Alarm stream: rings at alarm volume, even with media muted or the
    // phone on silent, like a clock app.
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          stayAwake: true,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.stop();
    await _player.play(AssetSource(sound.assetSourcePath), volume: 1.0);
    if (_player.state == PlayerState.playing) return true;
    try {
      await _player.onPlayerStateChanged
          .firstWhere((s) => s == PlayerState.playing)
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      // The caller keeps the notification's own sound playing instead.
      debugPrint('Alarm sound did not start: $e');
      return false;
    }
  }

  static Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _activeSoundId = null;
    await _player.stop();
  }
}
