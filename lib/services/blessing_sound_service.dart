// 祭江祈福音效：颂钵 + 河水混音，写法与 RiverAmbientService._loadAndPlay 一致。
// 时间线：颂钵起播，5 秒后混入河水，河水满音量 3 秒后淡出 2 秒结束。
//
// 关键设计原则（与 RiverAmbientService 完全对齐）：
//   1. player 先用局部变量持有，play() 确认后再赋给成员变量，避免 catchError 操作错误实例。
//   2. play() 不 await：bowl 单次播完即止，river 是 LoopMode.one，Future 永不结束。
//   3. catchError 只 dispose 局部 player，不碰成员变量，消除多次调用时的竞态。
//   4. 用 _session 标记当前轮次，异步回调中比对 session，旧轮次直接 dispose 并返回。

import 'dart:async';
import 'package:just_audio/just_audio.dart';

class BlessingSoundService {
  BlessingSoundService();

  static const String _bowl  = 'assets/audio/bowl.ogg';
  static const String _murmur = 'assets/audio/murmur_01.ogg';

  /// 混音权重：颂钵轨音量（0.0~1.0 标准；>1.0 部分设备会放大，可能削波）
  static const double bowlVolume = 1.2;
  /// 混音权重：河水轨音量（调低可让颂钵更突出）
  static const double riverVolume = 0.55;

  AudioPlayer? _bowlPlayer;
  AudioPlayer? _riverPlayer;
  Timer? _startRiverTimer;
  Timer? _fadeOutTimer;
  int _session = 0;

  /// 预加载：暂不使用，保留空实现以免调用处报错。
  void preloadBowl() {}

  /// 开播：颂钵 → 5 s 后河水 → 3 s 后淡出 2 s。
  /// 遵循 RiverAmbientService._loadAndPlay 的局部变量模式。
  void play() {
    _session++;
    final mySession = _session;

    _startRiverTimer?.cancel();
    _startRiverTimer = null;
    _fadeOutTimer?.cancel();
    _fadeOutTimer = null;
    _bowlPlayer?.dispose();
    _bowlPlayer = null;
    _riverPlayer?.dispose();
    _riverPlayer = null;

    // ── 颂钵轨 ────────────────────────────────────────────────────
    final bowlPlayer = AudioPlayer();
    bowlPlayer
        .setAsset(_bowl)
        .then((_) async {
          if (_session != mySession) {
            bowlPlayer.dispose();
            return;
          }
          await bowlPlayer.setVolume(bowlVolume);
          // ★ 不 await play()：bowl 单次播完即止，Future 完成后 player 自然结束
          bowlPlayer.play();
          if (_session != mySession) {
            bowlPlayer.dispose();
            return;
          }
          // 只在确认已播后才赋值给成员变量，避免 catchError 误操作
          _bowlPlayer = bowlPlayer;

          _startRiverTimer = Timer(const Duration(seconds: 5), () {
            if (_session != mySession) return;
            _startRiver(mySession);
          });
        })
        .catchError((e) {
          // PlayerInterruptedException = dispose() 在 setAsset 期间被调用，属正常中断
          // 只 dispose 局部变量，不碰 _bowlPlayer（可能已指向新实例）
          bowlPlayer.dispose();
        });
  }

  // ── 河水轨 ────────────────────────────────────────────────────
  void _startRiver(int mySession) {
    final riverPlayer = AudioPlayer();
    riverPlayer
        .setAsset(_murmur)
        .then((_) async {
          if (_session != mySession) {
            riverPlayer.dispose();
            return;
          }
          await riverPlayer.setLoopMode(LoopMode.one);
          await riverPlayer.setVolume(riverVolume);
          // ★ 不 await play()：LoopMode.one 的 Future 永远不会完成
          riverPlayer.play();
          if (_session != mySession) {
            riverPlayer.dispose();
            return;
          }
          _riverPlayer = riverPlayer;

          _fadeOutTimer = Timer(const Duration(seconds: 3), () {
            if (_session != mySession) return;
            _fadeOutAndDispose();
          });
        })
        .catchError((e) {
          riverPlayer.dispose();
        });
  }

  // ── 2 秒淡出（只淡出河水，颂钵保持满音量直到结束）─────────────────
  Future<void> _fadeOutAndDispose() async {
    const steps = 40;
    const stepMs = 50; // 40 × 50 ms = 2000 ms
    for (int i = 1; i <= steps; i++) {
      final v = 1.0 - (i / steps); // 河水从 riverVolume 淡到 0
      try {
        // 颂钵不参与淡出，保持 bowlVolume
        await _riverPlayer?.setVolume(riverVolume * v);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
    }
    _startRiverTimer?.cancel();
    _startRiverTimer = null;
    _fadeOutTimer?.cancel();
    _fadeOutTimer = null;
    _bowlPlayer?.dispose();
    _bowlPlayer = null;
    _riverPlayer?.dispose();
    _riverPlayer = null;
  }

  /// 立即取消当前轮次（dispose 时调）。
  void cancel() {
    _session++;
    _startRiverTimer?.cancel();
    _startRiverTimer = null;
    _fadeOutTimer?.cancel();
    _fadeOutTimer = null;
    _bowlPlayer?.dispose();
    _bowlPlayer = null;
    _riverPlayer?.dispose();
    _riverPlayer = null;
  }
}
