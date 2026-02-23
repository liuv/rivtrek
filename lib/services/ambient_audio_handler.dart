// lib/services/ambient_audio_handler.dart
// 音频逻辑在 AudioHandler 内，UI 只发 customAction(playAmbient/stopAmbient、playBlessing/preloadBlessingBowl/cancelBlessing)。
// 范例与约定见：docs/AMBIENT_AUDIO_REFERENCES.md（audio_service Tutorial / Example）

import 'package:audio_service/audio_service.dart';
import '../models/ambient_mix.dart';
import 'river_ambient_service.dart';
import 'blessing_sound_service.dart';

/// 河畔混音与祭江祈福音效均由 Handler 管理，加载与播放在 Handler 内执行
class AmbientAudioHandler extends BaseAudioHandler {
  AmbientAudioHandler() {
    _broadcastState(AudioProcessingState.idle, false);
  }

  final RiverAmbientService _service = RiverAmbientService();
  final BlessingSoundService _blessingSound = BlessingSoundService();

  void _broadcastState(AudioProcessingState state, bool playing) {
    playbackState.add(PlaybackState(
      controls: playing ? [MediaControl.stop] : [],
      processingState: state,
      playing: playing,
    ));
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'playAmbient' && extras != null) {
      _broadcastState(AudioProcessingState.loading, false);
      final spec = AmbientMixSpec.fromMap(extras);
      _service.play(spec);
      _broadcastState(AudioProcessingState.ready, true);
      return null;
    }
    if (name == 'stopAmbient') {
      _service.stop();
      _broadcastState(AudioProcessingState.idle, false);
      return null;
    }
    if (name == 'preloadBlessingBowl') {
      _blessingSound.preloadBowl();
      return null;
    }
    if (name == 'playBlessing') {
      _blessingSound.play();
      return null;
    }
    if (name == 'cancelBlessing') {
      _blessingSound.cancel();
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    _service.stop();
    _blessingSound.cancel();
    _broadcastState(AudioProcessingState.idle, false);
  }
}
