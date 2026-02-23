// lib/models/ambient_mix.dart
// 河畔实景混音：配方与音量规格，参见 docs/AMBIENT_MIX_DESIGN.md

import '../models/daily_stats.dart';

/// 单次混音的各层目标音量 (0~1)，用于多轨同时播放
class AmbientMixSpec {
  const AmbientMixSpec({
    required this.murmur,
    required this.rain,
    required this.wind,
    required this.frog,
    required this.rumble,
  });

  final double murmur;
  final double rain;
  final double wind;
  final double frog;
  final double rumble;

  /// 全局增益（ritual 略收、immersive 满电平）
  AmbientMixSpec applyContextGain(double gain) {
    return AmbientMixSpec(
      murmur: (murmur * gain).clamp(0.0, 1.0),
      rain: (rain * gain).clamp(0.0, 1.0),
      wind: (wind * gain).clamp(0.0, 1.0),
      frog: (frog * gain).clamp(0.0, 1.0),
      rumble: (rumble * gain).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'murmur': murmur,
        'rain': rain,
        'wind': wind,
        'frog': frog,
        'rumble': rumble,
      };

  static AmbientMixSpec fromMap(Map<String, dynamic> map) => AmbientMixSpec(
        murmur: (map['murmur'] as num?)?.toDouble() ?? 0,
        rain: (map['rain'] as num?)?.toDouble() ?? 0,
        wind: (map['wind'] as num?)?.toDouble() ?? 0,
        frog: (map['frog'] as num?)?.toDouble() ?? 0,
        rumble: (map['rumble'] as num?)?.toDouble() ?? 0,
      );
}

/// 使用场景
enum AmbientContext {
  /// 放河灯/漂流瓶仪式：河声略突出，总增益略收
  ritual,
  /// 沉浸听水/正念冥想：完整混音
  immersive,
}

/// 根据天气、昼夜、月份、场景计算混音配方
class AmbientMixRecipe {
  const AmbientMixRecipe._();

  static const double _ritualGain = 0.88;
  static const double _ritualMurmurBoost = 1.08;
  static const double _immersiveGain = 1.0;

  /// [weather] 当前天气类型（可由 wmoCode 映射）
  /// [isNight]  true = 夜间（如 hour < 6 || hour >= 18）
  /// [month]    1–12，用于蛙鸣季节系数（3–9 为 1.0，10–2 为 0.4）
  /// [context]  ritual | immersive
  static AmbientMixSpec compute(
    WeatherType weather, {
    required bool isNight,
    required int month,
    required AmbientContext context,
  }) {
    double murmur = 0.95;
    double rain = 0.0;
    double wind = 0.40;
    double frog = 0.0;
    double rumble = 0.0;

    switch (weather) {
      case WeatherType.clearSky:
        murmur = 1.0;
        wind = 0.35;
        frog = isNight ? 0.50 : 0.25;
        break;
      case WeatherType.mainlyClear:
        murmur = 1.0;
        wind = 0.38;
        frog = isNight ? 0.50 : 0.25;
        break;
      case WeatherType.partlyCloudy:
        murmur = 0.95;
        wind = 0.42;
        frog = isNight ? 0.50 : 0.25;
        break;
      case WeatherType.overcast:
        murmur = 0.92;
        wind = 0.45;
        frog = 0.15;
        break;
      case WeatherType.fog:
        murmur = 0.88;
        wind = 0.28;
        break;
      case WeatherType.drizzle:
        murmur = 0.85;
        rain = 0.45;
        wind = 0.40;
        break;
      case WeatherType.rainSlight:
        murmur = 0.82;
        rain = 0.55;
        wind = 0.45;
        break;
      case WeatherType.rainModerate:
        murmur = 0.78;
        rain = 0.68;
        wind = 0.50;
        break;
      case WeatherType.rainHeavy:
        murmur = 0.72;
        rain = 0.82;
        wind = 0.55;
        break;
      case WeatherType.rainShowers:
        murmur = 0.75;
        rain = 0.70;
        wind = 0.52;
        break;
      case WeatherType.thunderstorm:
        murmur = 0.70;
        rain = 0.75;
        wind = 0.50;
        rumble = 0.45;
        break;
      case WeatherType.thunderstormHail:
        murmur = 0.68;
        rain = 0.78;
        wind = 0.52;
        rumble = 0.55;
        break;
      case WeatherType.freezingDrizzle:
      case WeatherType.freezingRain:
        murmur = 0.82;
        rain = 0.50;
        wind = 0.48;
        break;
      case WeatherType.snowSlight:
      case WeatherType.snowModerate:
      case WeatherType.snowHeavy:
      case WeatherType.snowGrains:
      case WeatherType.snowShowers:
        murmur = 0.85;
        wind = 0.48;
        break;
      case WeatherType.unknown:
        murmur = 0.95;
        wind = 0.40;
        frog = isNight ? 0.50 : 0.25;
        break;
    }

    // 蛙鸣季节：3–9 月 1.0，10–2 月 0.4
    final frogSeason = (month >= 3 && month <= 9) ? 1.0 : 0.4;
    frog = frog * frogSeason;

    // 夜间无降水时风略降
    if (isNight && rain <= 0 && rumble <= 0) {
      wind *= 0.92;
    }

    var spec = AmbientMixSpec(
      murmur: murmur,
      rain: rain,
      wind: wind,
      frog: frog,
      rumble: rumble,
    );

    final gain = context == AmbientContext.ritual ? _ritualGain : _immersiveGain;
    spec = spec.applyContextGain(gain);
    if (context == AmbientContext.ritual) {
      spec = AmbientMixSpec(
        murmur: (spec.murmur * _ritualMurmurBoost).clamp(0.0, 1.0),
        rain: spec.rain,
        wind: spec.wind,
        frog: spec.frog,
        rumble: spec.rumble,
      );
    }
    return spec;
  }

  /// 从 WMO 天气码映射到 WeatherType（与 flow_screen 一致）
  static WeatherType weatherTypeFromWmoCode(int code) {
    if (code == 0) return WeatherType.clearSky;
    if (code <= 3) return WeatherType.partlyCloudy;
    if (code <= 48) return WeatherType.fog;
    if (code <= 55) return WeatherType.drizzle;
    if (code <= 65) return WeatherType.rainModerate;
    if (code <= 75) return WeatherType.snowModerate;
    if (code <= 82) return WeatherType.rainShowers;
    if (code <= 99) return WeatherType.thunderstorm;
    return WeatherType.unknown;
  }
}
