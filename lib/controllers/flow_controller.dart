// lib/controllers/flow_controller.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import '../models/daily_stats.dart';
import '../models/river_section.dart';
import '../services/database_service.dart';
import '../providers/challenge_provider.dart';

class FlowController extends ChangeNotifier {
  // 步数与里程
  int _displaySteps = 0;
  double _currentDistance = 0.0;
  int _lastSavedSteps = 0;
  final double _stepLengthKm = 0.0007; 
  
  // 天气相关
  String _temp = "--";
  String _maxTemp = "--";
  String _minTemp = "--";
  String _cityName = "待定位";
  int _wmoCode = 0;
  double _lat = 0.0;
  double _lon = 0.0;
  double _windSpeed = 0.0;

  // 数据引用 (通过 ChallengeProvider 同步)
  List<SubSection> _allSubSections = [];
  SubSection? _currentSubSection;
  String? _activeRiverId;

  // Getters
  int get displaySteps => _displaySteps;
  double get currentDistance => _currentDistance;
  String get temp => _temp;
  String get maxTemp => _maxTemp;
  String get minTemp => _minTemp;
  String get cityName => _cityName;
  int get wmoCode => _wmoCode;
  double get lat => _lat;
  double get lon => _lon;
  double get windSpeed => _windSpeed;
  List<SubSection> get allSubSections => _allSubSections;
  SubSection? get currentSubSection => _currentSubSection;

  StreamSubscription? _pedometerSubscription;
  final Health health = Health();

  Future<void> init() async {
    await _loadCachedWeather();
  }

  // 被 ChallengeProvider 调用，实现状态同步
  void updateFromChallenge(ChallengeProvider challenge) {
    if (challenge.isLoading) return;
    
    bool riverChanged = _activeRiverId != challenge.activeRiver?.id;
    
    _allSubSections = challenge.allSubSections;
    _currentSubSection = challenge.currentSubSection;
    _currentDistance = challenge.currentDistance;
    _activeRiverId = challenge.activeRiver?.id;

    if (riverChanged) {
      // 如果切换了河流，重新计算步数（或根据河流进度恢复）
      // 这里暂定步数是全球/当日共享，但里程按河流进度走
      _displaySteps = (_currentDistance / _stepLengthKm).round();
    }
    
    notifyListeners();
  }

  void startStepListening() {
    _pedometerSubscription = Pedometer.stepCountStream.listen((event) async {
      final prefs = await SharedPreferences.getInstance();
      final String today = DateTime.now().toString().split(' ')[0];
      int hardwareTotal = event.steps;
      int base = prefs.getInt('base_steps_value') ?? hardwareTotal;
      
      if (prefs.getString('last_sync_date') != today || hardwareTotal < base) {
        await prefs.setString('last_sync_date', today);
        await prefs.setInt('base_steps_value', hardwareTotal);
        base = hardwareTotal;
      }
      
      _displaySteps = hardwareTotal - base;
      _currentDistance = _displaySteps * _stepLengthKm;
      
      // 注意：这里需要通知 ChallengeProvider 更新其持有的距离
      // 但在 ProxyProvider 模式下，通常是 ChallengeProvider 驱动 FlowController
      // 为了避免循环依赖，我们可以在这里直接保存进度到 SharedPreferences
      // 或者提供一个回调。这里选择直接保存进度，ChallengeProvider 监听存储或通过 UI 触发更新。
      
      final activeId = prefs.getString('active_river_id') ?? 'yangtze';
      await prefs.setDouble('progress_$activeId', _currentDistance);
      
      notifyListeners();
    });
  }

  Future<void> saveToDatabase({bool force = false}) async {
    if (!force && (_displaySteps - _lastSavedSteps).abs() < 500) return;
    
    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await DatabaseService.instance.saveActivity(DailyActivity(
        date: date,
        steps: _displaySteps,
        distanceKm: _displaySteps * _stepLengthKm,
        accumulatedDistanceKm: _currentDistance,
      ));
      
      if (_wmoCode != 0) {
        await DatabaseService.instance.saveWeather(DailyWeather(
          date: date,
          wmoCode: _wmoCode,
          currentTemp: _temp,
          maxTemp: _maxTemp,
          minTemp: _minTemp,
          windSpeed: _windSpeed,
          cityName: _cityName,
          latitude: _lat,
          longitude: _lon,
        ));
      }
      _lastSavedSteps = _displaySteps;
    } catch (e) {
      debugPrint("DB Save Error: $e");
    }
  }

  Future<void> fetchWeather(double lat, double lon) async {
    _lat = lat; _lon = lon;
    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=temperature_2m_max,temperature_2m_min&timezone=auto');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _temp = "${data['current_weather']['temperature']}°";
        _wmoCode = data['current_weather']['weathercode'];
        _windSpeed = data['current_weather']['windspeed'];
        _maxTemp = "${data['daily']['temperature_2m_max'][0]}°";
        _minTemp = "${data['daily']['temperature_2m_min'][0]}°";
        
        final cityUrl = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=zh');
        final cityRes = await http.get(cityUrl);
        if (cityRes.statusCode == 200) {
          _cityName = json.decode(cityRes.body)['city'] ?? "未知地点";
        }
        
        _saveWeatherToCache();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Fetch weather error: $e");
    }
  }

  Future<void> _loadCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString('cached_weather_v2');
    if (cached != null) {
      final data = json.decode(cached);
      _temp = data['temp'];
      _cityName = data['city'];
      _wmoCode = data['wmo_code'];
      _maxTemp = data['max_temp'];
      _minTemp = data['min_temp'];
      notifyListeners();
    }
  }

  void _saveWeatherToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_weather_v2', json.encode({
      'temp': _temp, 'city': _cityName, 'wmo_code': _wmoCode,
      'max_temp': _maxTemp, 'min_temp': _minTemp, 'lat': _lat, 'lon': _lon
    }));
  }

  @override
  void dispose() {
    _pedometerSubscription?.cancel();
    super.dispose();
  }
}
