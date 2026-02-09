import 'package:flutter/material.dart';

/// 遵循 WMO (World Meteorological Organization) 标准的天气分类
enum WeatherType {
  clearSky,           // 0: 晴朗
  mainlyClear,        // 1: 大部晴朗
  partlyCloudy,       // 2: 多云
  overcast,           // 3: 阴天
  fog,                // 45, 48: 雾
  drizzle,            // 51, 53, 55: 毛毛雨
  freezingDrizzle,    // 56, 57: 冻毛毛雨
  rainSlight,         // 61: 小雨
  rainModerate,       // 63: 中雨
  rainHeavy,          // 65: 大雨/阵雨
  freezingRain,       // 66, 67: 冻雨
  snowSlight,         // 71: 小雪
  snowModerate,       // 73: 中雪
  snowHeavy,          // 75: 大雪
  snowGrains,         // 77: 雪粒
  rainShowers,        // 80, 81, 82: 阵雨
  snowShowers,        // 85, 86: 阵雪
  thunderstorm,       // 95: 雷暴
  thunderstormHail,   // 96, 99: 雷暴伴有冰雹
  unknown,
}

extension WeatherTypeExtension on WeatherType {
  String get label {
    switch (this) {
      case WeatherType.clearSky: return "晴朗";
      case WeatherType.mainlyClear: return "大部晴朗";
      case WeatherType.partlyCloudy: return "多云";
      case WeatherType.overcast: return "阴天";
      case WeatherType.fog: return "雾";
      case WeatherType.drizzle: return "毛毛雨";
      case WeatherType.freezingDrizzle: return "冻毛毛雨";
      case WeatherType.rainSlight: return "小雨";
      case WeatherType.rainModerate: return "中雨";
      case WeatherType.rainHeavy: return "大/暴雨";
      case WeatherType.freezingRain: return "冻雨";
      case WeatherType.snowSlight: return "小雪";
      case WeatherType.snowModerate: return "中雪";
      case WeatherType.snowHeavy: return "大雪";
      case WeatherType.snowGrains: return "雪粒";
      case WeatherType.rainShowers: return "强阵雨";
      case WeatherType.snowShowers: return "阵雪";
      case WeatherType.thunderstorm: return "雷暴";
      case WeatherType.thunderstormHail: return "雷雨冰雹";
      case WeatherType.unknown: return "未知";
    }
  }

  IconData get icon {
    switch (this) {
      case WeatherType.clearSky: return Icons.wb_sunny_outlined;
      case WeatherType.mainlyClear: return Icons.wb_cloudy_outlined;
      case WeatherType.partlyCloudy: return Icons.wb_cloudy_rounded;
      case WeatherType.overcast: return Icons.cloud_queue_rounded;
      case WeatherType.fog: return Icons.blur_on_rounded;
      case WeatherType.drizzle: return Icons.umbrella_outlined;
      case WeatherType.freezingDrizzle: return Icons.ac_unit_outlined;
      case WeatherType.rainSlight: return Icons.umbrella_rounded;
      case WeatherType.rainModerate: return Icons.grain_rounded;
      case WeatherType.rainHeavy: return Icons.beach_access_rounded;
      case WeatherType.freezingRain: return Icons.ac_unit_rounded;
      case WeatherType.snowSlight: return Icons.ac_unit_outlined;
      case WeatherType.snowModerate: return Icons.ac_unit_rounded;
      case WeatherType.snowHeavy: return Icons.severe_cold_rounded;
      case WeatherType.snowGrains: return Icons.grain_outlined;
      case WeatherType.rainShowers: return Icons.water_drop_rounded;
      case WeatherType.snowShowers: return Icons.snowboarding_rounded;
      case WeatherType.thunderstorm: return Icons.thunderstorm_rounded;
      case WeatherType.thunderstormHail: return Icons.flash_on_rounded;
      case WeatherType.unknown: return Icons.help_outline_rounded;
    }
  }
}

// 步数与里程统计 (高频写)
class DailyActivity {
  final String date; 
  final int steps;
  final double distanceKm;
  final double accumulatedDistanceKm;

  DailyActivity({
    required this.date,
    required this.steps,
    required this.distanceKm,
    required this.accumulatedDistanceKm,
  });

  Map<String, dynamic> toMap() => {
    'date': date,
    'steps': steps,
    'distance_km': distanceKm,
    'accumulated_distance_km': accumulatedDistanceKm,
  };

  factory DailyActivity.fromMap(Map<String, dynamic> map) => DailyActivity(
    date: map['date'],
    steps: (map['steps'] as int),
    distanceKm: (map['distance_km'] as num).toDouble(),
    accumulatedDistanceKm: (map['accumulated_distance_km'] as num).toDouble(),
  );
}

// 每日天气快照 (覆盖写)
class DailyWeather {
  final String date;
  final int wmoCode;
  final String currentTemp;
  final String maxTemp;
  final String minTemp;
  final double windSpeed;
  final String cityName;
  final double latitude;
  final double longitude;

  DailyWeather({
    required this.date,
    required this.wmoCode,
    required this.currentTemp,
    required this.maxTemp,
    required this.minTemp,
    required this.windSpeed,
    required this.cityName,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'date': date,
    'wmo_code': wmoCode,
    'current_temp': currentTemp,
    'max_temp': maxTemp,
    'min_temp': minTemp,
    'wind_speed': windSpeed,
    'city_name': cityName,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory DailyWeather.fromMap(Map<String, dynamic> map) => DailyWeather(
    date: map['date'],
    wmoCode: map['wmo_code'],
    currentTemp: map['current_temp'],
    maxTemp: map['max_temp'],
    minTemp: map['min_temp'],
    windSpeed: (map['wind_speed'] as num).toDouble(),
    cityName: map['city_name'],
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
  );
}

// 河流事件 (拾遗、祭祀、勋章等)
enum RiverEventType { pickup, activity, achievement }

class RiverEvent {
  final int? id;
  final String date;
  final int timestamp;
  final RiverEventType type;
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final double distanceAtKm;
  final String extraData;

  RiverEvent({
    this.id,
    required this.date,
    required this.timestamp,
    required this.type,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.distanceAtKm,
    this.extraData = "{}",
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'timestamp': timestamp,
    'type': type.name,
    'name': name,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'distance_at_km': distanceAtKm,
    'extra_data': extraData,
  };
}
