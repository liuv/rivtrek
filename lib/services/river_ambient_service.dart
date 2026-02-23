// lib/services/river_ambient_service.dart
// 河畔实景多轨混音：按 AmbientMixSpec 多轨播放 murmur/rain/wind/frog/rumble。
// just_audio 多 player、stop/dispose、PlayerInterruptedException 等见：docs/AMBIENT_AUDIO_REFERENCES.md
//
// 关键设计原则（来自 just_audio 文档 + 实测）：
//   1. player.play() 的 Future 在播放结束时才完成，LoopMode.one 永远不结束，绝对不能 await。
//   2. 停止 player 只需调 dispose()，just_audio 内部会处理 stop；分开调 stop()+dispose() 
//      可能触发 "Cannot complete a future with itself" 异常。
//   3. 用 _session（int 自增）标记当前播放轮次；setAsset.then() 里比对 session，
//      若已变更则直接 dispose 并返回，避免旧轮次的 player 混入当前 _players。

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/ambient_mix.dart';

class AmbientAssets {
  const AmbientAssets._();
  static const String murmur = 'assets/audio/murmur_01.ogg';
  static const String rain   = 'assets/audio/rain.ogg';
  static const String wind   = 'assets/audio/wind.ogg';
  static const String frog   = 'assets/audio/frog.ogg';
  static const String rumble = 'assets/audio/rumble.ogg';
}

class RiverAmbientService {
  RiverAmbientService();

  /// 每次 play/stop 自增，用于丢弃旧轮次的异步结果
  int _session = 0;
  final List<AudioPlayer> _players = [];

  bool get isPlaying => _players.isNotEmpty;

  // ─── 公开接口 ──────────────────────────────────────────

  /// 按 spec 播放混音；立即停掉当前在播的轨，再逐轨异步加载后立即播出
  void play(AmbientMixSpec spec) {
    _session++;
    final mySession = _session;
    if (kDebugMode) {
      debugPrint('[Ambient] play session=$mySession '
          'murmur=${spec.murmur} wind=${spec.wind} '
          'rain=${spec.rain} frog=${spec.frog} rumble=${spec.rumble}');
    }
    _disposeAll();

    final toLoad = <String, double>{};
    if (spec.murmur > 0) toLoad[AmbientAssets.murmur] = spec.murmur;
    if (spec.rain   > 0) toLoad[AmbientAssets.rain]   = spec.rain;
    if (spec.wind   > 0) toLoad[AmbientAssets.wind]   = spec.wind;
    if (spec.frog   > 0) toLoad[AmbientAssets.frog]   = spec.frog;
    if (spec.rumble > 0) toLoad[AmbientAssets.rumble] = spec.rumble;

    for (final entry in toLoad.entries) {
      _loadAndPlay(entry.key, entry.value, mySession);
    }
  }

  /// 停止所有轨并释放资源
  void stop() {
    _session++;
    if (kDebugMode) debugPrint('[Ambient] stop session=$_session');
    _disposeAll();
  }

  void dispose() => stop();

  // ─── 内部实现 ──────────────────────────────────────────

  void _loadAndPlay(String path, double vol, int mySession) {
    final player = AudioPlayer();
    player
        .setAsset(path)
        .then((_) async {
          // session 已变更 → 这一轮已被取消，直接释放
          if (_session != mySession) {
            if (kDebugMode) debugPrint('[Ambient] session stale, discard $path');
            player.dispose();
            return;
          }
          await player.setLoopMode(LoopMode.one);
          await player.setVolume(vol);
          // ★ 不 await play()：LoopMode.one 的 Future 永远不会完成
          player.play();
          // 再次检查：setLoopMode/setVolume 是 await 的，期间 session 可能已变
          if (_session != mySession) {
            player.dispose();
            return;
          }
          _players.add(player);
          if (kDebugMode) debugPrint('[Ambient] playing $path vol=$vol, total=${_players.length}');
        })
        .catchError((e) {
          // PlayerInterruptedException = dispose() 在 setAsset 完成前被调用，属正常中断
          if (e is! PlayerInterruptedException && kDebugMode) {
            debugPrint('[Ambient] load failed $path: $e');
          }
          player.dispose();
        });
  }

  void _disposeAll() {
    if (_players.isEmpty) return;
    final copy = List<AudioPlayer>.from(_players);
    _players.clear();
    if (kDebugMode) debugPrint('[Ambient] disposeAll ${copy.length} players');
    for (final p in copy) {
      // 只调 dispose()，just_audio 内部会 stop；分开调会触发 "Cannot complete future with itself"
      p.dispose();
    }
  }
}
