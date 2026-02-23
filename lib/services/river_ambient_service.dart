// lib/services/river_ambient_service.dart
// 河畔实景多轨混音：按 AmbientMixSpec 多轨播放 murmur/rain/wind/frog/rumble。
// just_audio 多 player、stop/dispose、PlayerInterruptedException 等见：docs/AMBIENT_AUDIO_REFERENCES.md

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/ambient_mix.dart';

/// 各层素材路径（均为 OGG）
class AmbientAssets {
  const AmbientAssets._();
  static const String murmur = 'assets/audio/murmur_01.ogg';
  static const String rain = 'assets/audio/rain.ogg';
  static const String wind = 'assets/audio/wind.ogg';
  static const String frog = 'assets/audio/frog.ogg';
  static const String rumble = 'assets/audio/rumble.ogg';
}

/// 单层播放句柄：player + 目标音量
class _LayerHandle {
  _LayerHandle(this.player, this.targetVolume);
  final AudioPlayer player;
  final double targetVolume;
}

/// 河畔实景混音播放服务：多轨循环、统一淡入淡出
class RiverAmbientService {
  RiverAmbientService();

  final List<_LayerHandle> _layers = [];
  bool _disposed = false;
  bool _stopRequested = false;
  /// 正在 setAsset 的 player。just_audio 文档：load 完成前对 player 调用 stop/dispose 会使 setAsset 抛出 PlayerInterruptedException，属预期中断方式；stopSyncAsync 会立即 dispose 此引用以中断加载。
  AudioPlayer? _loadingPlayer;

  /// 当前配方（用于淡出时按比例降）
  AmbientMixSpec? _currentSpec;

  static Future<void> _stopOnePlayer(AudioPlayer p) async {
    try {
      await p.stop().timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}
    try {
      await p.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}
  }

  /// 是否正在播放
  bool get isPlaying => _layers.any((h) => h.player.playing);

  /// 按 [spec] 加载并播放，只加载 volume > 0 的层。不阻塞 UI：先让出主线程再加载，每加载一层再让出一次。
  void play(AmbientMixSpec spec, {Duration? fadeIn}) {
    Future.microtask(() => _playImpl(spec, fadeIn: fadeIn));
  }

  Future<void> _playImpl(AmbientMixSpec spec, {Duration? fadeIn}) async {
    if (_disposed) return;
    // 官方约定：新 session 前先中止仍在加载的上一轮，避免两套 _playImpl 同时往 _layers 加 player
    _stopRequested = true;
    await stop();
    if (_disposed) return;
    _stopRequested = false;
    _currentSpec = spec;

    final toLoad = <String, double>{};
    if (spec.murmur > 0) toLoad[AmbientAssets.murmur] = spec.murmur;
    if (spec.rain > 0) toLoad[AmbientAssets.rain] = spec.rain;
    if (spec.wind > 0) toLoad[AmbientAssets.wind] = spec.wind;
    if (spec.frog > 0) toLoad[AmbientAssets.frog] = spec.frog;
    if (spec.rumble > 0) toLoad[AmbientAssets.rumble] = spec.rumble;

    if (kDebugMode) {
      debugPrint('[Ambient] _playImpl toLoad: ${toLoad.length} layers, $toLoad');
    }

    for (final entry in toLoad.entries) {
      if (_disposed || _stopRequested) return;
      await Future.delayed(Duration.zero);
      if (_stopRequested) return;
      final player = AudioPlayer();
      _loadingPlayer = player;
      try {
        if (kDebugMode) debugPrint('[Ambient] loading ${entry.key} vol=${entry.value}');
        await player.setAsset(entry.key);
        // 不在此处清 _loadingPlayer：从 play() 到 _layers.add() 之间已出声但尚未进列表，必须仍视为“正在加载”以便 stopSyncAsync 能停掉
        if (_disposed || _stopRequested) {
          await _stopOnePlayer(player);
          return;
        }
        await player.setLoopMode(LoopMode.one);
        if (_disposed || _stopRequested) {
          await _stopOnePlayer(player);
          return;
        }
        final vol = fadeIn != null ? 0.0 : entry.value;
        await player.setVolume(vol);
        if (_disposed || _stopRequested) {
          await _stopOnePlayer(player);
          return;
        }
        await player.play();
        if (_disposed || _stopRequested) {
          await _stopOnePlayer(player);
          return;
        }
        _layers.add(_LayerHandle(player, entry.value));
        _loadingPlayer = null; // 已进列表，之后由 _layers 管理
        if (kDebugMode) debugPrint('[Ambient] started ${entry.key}, layers=${_layers.length}');
      } catch (e) {
        _loadingPlayer = null;
        // just_audio：stop/dispose 在 load 完成前会抛 PlayerInterruptedException，属正常中断，非加载失败
        if (e is! PlayerInterruptedException && kDebugMode) {
          debugPrint('[Ambient] failed to load ${entry.key}: $e');
        }
        await _stopOnePlayer(player);
      }
    }

    if (fadeIn != null && _layers.isNotEmpty) {
      _runFadeIn(fadeIn);
    }
  }

  void _runFadeIn(Duration duration) {
    const steps = 24;
    final stepMs = duration.inMilliseconds / steps;
    final stepDuration = Duration(milliseconds: stepMs.round());
    var step = 0;
    void tick() {
      if (_disposed || _layers.isEmpty) return;
      step++;
      final t = (step / steps).clamp(0.0, 1.0);
      for (final h in _layers) {
        h.player.setVolume(h.targetVolume * t);
      }
      if (step < steps) {
        Future.delayed(stepDuration, tick);
      }
    }
    Future.delayed(stepDuration, tick);
  }

  /// 淡出并停止、释放所有 player。必须 await 完成，否则旧 session 会变成“孤儿”继续播。
  /// 新 session 开始时也会调用，此时要连同 _loadingPlayer 一起停掉（just_audio 多 player 范例：await stop 释放）。
  Future<void> stop({Duration? fadeOut}) async {
    final loading = _loadingPlayer;
    _loadingPlayer = null;
    if (_layers.isEmpty && loading == null) return;
    final spec = _currentSpec;
    final list = List<_LayerHandle>.from(_layers);
    _layers.clear();
    _currentSpec = null;

    if (fadeOut != null && fadeOut.inMilliseconds > 0 && spec != null) {
      const steps = 12;
      final stepMs = fadeOut.inMilliseconds / steps;
      for (var i = steps; i >= 0; i--) {
        final v = (i / steps) * 1.0;
        for (final h in list) {
          h.player.setVolume(h.targetVolume * v);
        }
        await Future.delayed(Duration(milliseconds: stepMs.round()));
      }
    }

    final toStop = <AudioPlayer>[for (final h in list) h.player];
    if (loading != null) toStop.add(loading);
    await Future.wait(toStop.map(_stopOnePlayer));
  }

  /// 退出时调用：立即清空列表并停止/释放所有 player，不 await，避免阻塞 dispose
  void stopSync() {
    _stopRequested = true;
    final loading = _loadingPlayer;
    _loadingPlayer = null;
    if (loading != null) {
      loading.stop();
      loading.dispose();
    }
    if (_layers.isEmpty) {
      if (kDebugMode) debugPrint('[Ambient] stopSync: no layers');
      return;
    }
    final list = List<_LayerHandle>.from(_layers);
    _layers.clear();
    _currentSpec = null;
    if (kDebugMode) debugPrint('[Ambient] stopSync: stopping ${list.length} players');
    for (final h in list) {
      h.player.stop();
      h.player.dispose();
    }
  }

  /// 异步停止并等待所有 player 真正停掉；立即 dispose _loadingPlayer 以中断 setAsset（just_audio 会抛 PlayerInterruptedException）
  Future<void> stopSyncAsync() async {
    _stopRequested = true;
    final loading = _loadingPlayer;
    _loadingPlayer = null;
    if (loading != null) {
      if (kDebugMode) debugPrint('[Ambient] stopSyncAsync: stopping loading player immediately');
      await _stopOnePlayer(loading);
    }
    if (_layers.isEmpty) {
      if (kDebugMode) debugPrint('[Ambient] stopSyncAsync: no layers');
      return;
    }
    final list = List<_LayerHandle>.from(_layers);
    _layers.clear();
    _currentSpec = null;
    if (kDebugMode) debugPrint('[Ambient] stopSyncAsync: stopping ${list.length} players');
    await Future.wait([
      for (final h in list) _stopOnePlayer(h.player),
    ]);
    if (kDebugMode) debugPrint('[Ambient] stopSyncAsync: done');
  }

  void dispose() {
    _disposed = true;
    stopSync();
  }
}
