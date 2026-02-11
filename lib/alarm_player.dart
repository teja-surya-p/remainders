import 'package:audioplayers/audioplayers.dart';

class AlarmPlayer {
  AlarmPlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('alarm.wav'), volume: 1.0);
  }

  static Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _player.stop();
  }
}
