import 'package:audioplayers/audioplayers.dart';

import 'reminder_sounds.dart';

class SoundPreviewPlayer {
  SoundPreviewPlayer._();

  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play(ReminderSoundOption option) async {
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.play(AssetSource(option.assetSourcePath), volume: 1.0);
  }

  static Future<void> stop() async {
    await _player.stop();
  }
}
