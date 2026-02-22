import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RiverPathMode {
  procedural,
  realPath,
}

enum RiverStyle {
  classic,
  ink,
  aurora,
}

/// 河灯/漂流瓶漂浮速度倍数范围：0.02x～2x，1x = 60 秒过一屏
const double kDriftCrossScreenMinSeconds = 30;   // 2x，最快（60/2）
const double kDriftCrossScreenMaxSeconds = 3000; // 0.02x，最慢（60/0.02）
const double kDriftCrossScreenDefaultSeconds = 60; // 1x

class RiverSettings extends ChangeNotifier {
  static final RiverSettings instance = RiverSettings();

  RiverPathMode _pathMode;
  RiverStyle _style;
  double _speed;
  double _turbulence;
  double _width;
  /// 河灯/漂流瓶整体漂浮速度倍数（内部用过屏时间秒数表示，1x = 60 秒，倍数 = 60/秒）
  double _driftCrossScreenSeconds;

  RiverSettings({
    RiverPathMode pathMode = RiverPathMode.procedural,
    RiverStyle style = RiverStyle.classic,
    double speed = 0.3,
    double turbulence = 0.6,
    double width = 0.18,
    double driftCrossScreenSeconds = kDriftCrossScreenDefaultSeconds,
  })  : _pathMode = pathMode,
        _style = style,
        _speed = speed,
        _turbulence = turbulence,
        _width = width,
        _driftCrossScreenSeconds = driftCrossScreenSeconds.clamp(
            kDriftCrossScreenMinSeconds, kDriftCrossScreenMaxSeconds);

  RiverPathMode get pathMode => _pathMode;
  RiverStyle get style => _style;
  double get speed => _speed;
  double get turbulence => _turbulence;
  double get width => _width;
  double get driftCrossScreenSeconds => _driftCrossScreenSeconds;

  void update({
    RiverPathMode? pathMode,
    RiverStyle? style,
    double? speed,
    double? turbulence,
    double? width,
    double? driftCrossScreenSeconds,
  }) {
    _pathMode = pathMode ?? _pathMode;
    _style = style ?? _style;
    _speed = speed ?? _speed;
    _turbulence = turbulence ?? _turbulence;
    _width = width ?? _width;
    if (driftCrossScreenSeconds != null) {
      _driftCrossScreenSeconds = driftCrossScreenSeconds
          .clamp(kDriftCrossScreenMinSeconds, kDriftCrossScreenMaxSeconds);
    }
    notifyListeners();
  }

  /// 从 SharedPreferences 加载并应用已保存的河流/漂流设置（启动时或恢复备份后调用）
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    instance.update(
      pathMode: RiverPathMode.values[prefs.getInt('river_path_mode') ?? 0],
      style: RiverStyle.values[prefs.getInt('river_style') ?? 0],
      speed: prefs.getDouble('river_speed') ?? 0.3,
      turbulence: prefs.getDouble('river_turbulence') ?? 0.6,
      width: prefs.getDouble('river_width') ?? 0.18,
      driftCrossScreenSeconds:
          prefs.getDouble('drift_cross_screen_seconds') ?? kDriftCrossScreenDefaultSeconds,
    );
  }
}
