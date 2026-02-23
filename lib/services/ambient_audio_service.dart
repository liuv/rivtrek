// lib/services/ambient_audio_service.dart
// UI 只调 playAmbient/stopAmbient，由 audio_service 转给 Handler 执行。
// 设计依据与官方范例：docs/AMBIENT_AUDIO_REFERENCES.md

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../models/ambient_mix.dart';
import 'ambient_audio_handler.dart';

/// 河畔混音入口：由 audio_service 管理，UI 只调 playAmbient/stopAmbient，不 await
class AmbientAudioService {
  AmbientAudioService._();

  static AudioHandler? _handler;

  /// 在 main() 中调用一次；Android 需配置 AndroidManifest
  static Future<void> init() async {
    if (_handler != null) return;
    _handler = await AudioService.init(
      builder: () => AmbientAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'cn.lindenliu.rivtrek.ambient',
        androidNotificationChannelName: '河声',
      ),
    );
    if (kDebugMode) debugPrint('[Ambient] init ok, handler=${_handler != null}');
  }

  /// 开始混音（不 await，由 Handler 在后台加载与播放）
  static void playAmbient(AmbientMixSpec spec) {
    if (kDebugMode) {
      debugPrint('[Ambient] playAmbient spec: murmur=${spec.murmur} rain=${spec.rain} wind=${spec.wind} frog=${spec.frog} rumble=${spec.rumble}');
    }
    _handler?.customAction('playAmbient', spec.toMap());
  }

  /// 停止混音（退出仪式/听水时调用）
  static void stopAmbient() {
    if (kDebugMode) debugPrint('[Ambient] stopAmbient called, handler=${_handler != null}');
    _handler?.customAction('stopAmbient');
  }

  /// 祭江祈福：预加载颂钵（打开仪式 sheet 时调，不 await）
  static void preloadBlessingBowl() {
    _handler?.customAction('preloadBlessingBowl');
  }

  /// 祭江祈福：开播颂钵 → 5s 后混入河水，河水播 3s 后淡出 2s 结束（不 await，由 Handler 执行）
  static void playBlessing() {
    _handler?.customAction('playBlessing');
  }

  /// 祭江祈福：取消当前轮次（dispose 时调）
  static void cancelBlessing() {
    _handler?.customAction('cancelBlessing');
  }
}
