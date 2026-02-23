// lib/services/ambient_audio_handler.dart
// 音频逻辑在 AudioHandler 内，UI 只发 customAction(playAmbient/stopAmbient)。
// 范例与约定见：docs/AMBIENT_AUDIO_REFERENCES.md（audio_service Tutorial / Example）

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../models/ambient_mix.dart';
import 'river_ambient_service.dart';

/// 河畔混音由系统音频服务管理，加载与播放均在 Handler 内执行，不占 UI 线程
class AmbientAudioHandler extends BaseAudioHandler {
  AmbientAudioHandler() {
    _broadcastState(AudioProcessingState.idle, false);
  }

  final RiverAmbientService _service = RiverAmbientService();

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
      if (kDebugMode) debugPrint('[Ambient] handler playAmbient');
      _broadcastState(AudioProcessingState.loading, false);
      final spec = AmbientMixSpec.fromMap(extras);
      _service.play(spec);
      _broadcastState(AudioProcessingState.ready, true);
      return null;
    }
    if (name == 'stopAmbient') {
      if (kDebugMode) debugPrint('[Ambient] handler stopAmbient');
      _service.stop();
      _broadcastState(AudioProcessingState.idle, false);
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    if (kDebugMode) debugPrint('[Ambient] handler stop()');
    _service.stop();
    _broadcastState(AudioProcessingState.idle, false);
  }
}
