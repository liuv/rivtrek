// lib/controllers/flow_controller.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';
import '../models/daily_stats.dart';
import '../models/river_section.dart';
import '../services/database_service.dart';
import '../providers/challenge_provider.dart';

import '../services/step_sync_service.dart';

class FlowController extends ChangeNotifier {
  // 步数与里程
  int _displaySteps = 0;
  double _currentDistance = 0.0;
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
  String _humidity = "--";
  String _apparentTemp = "--";
  String _aqi = "--";
  String _pm2_5 = "--";

  // 数据引用 (通过 ChallengeProvider 同步)
  ChallengeProvider? _challengeProvider;
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
  String get humidity => _humidity;
  String get apparentTemp => _apparentTemp;
  String get aqi => _aqi;
  String get pm2_5 => _pm2_5;
  List<SubSection> get allSubSections => _allSubSections;
  SubSection? get currentSubSection => _currentSubSection;

  StreamSubscription? _pedometerSubscription;
  Timer? _refreshTimer;

  Future<void> init() async {
    await _loadCachedWeather();
    // 启动时进行一次全量同步，补全可能缺失的步数
    await StepSyncService.syncAll();
    await _updateUIFromDB();
  }

  /// 从数据库刷新 UI 显示的数据
  Future<void> _updateUIFromDB() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final riverId = _activeRiverId ?? 'yangtze';
    
    final db = await DatabaseService.instance.database;
    final maps = await db.query('daily_activities', 
        where: 'date = ? AND river_id = ?', 
        whereArgs: [today, riverId]);
    
    if (maps.isNotEmpty) {
      final activity = DailyActivity.fromMap(maps.first);
      _displaySteps = activity.steps;
      _currentDistance = activity.accumulatedDistanceKm;
      _challengeProvider?.syncRealDistance(_currentDistance);
      notifyListeners();
    }
  }

  // 被 ChallengeProvider 调用，实现状态同步
  void updateFromChallenge(ChallengeProvider challenge) {
    _challengeProvider = challenge;
    if (challenge.isLoading) return;
    
    bool riverChanged = _activeRiverId != challenge.activeRiver?.id;
    
    _allSubSections = challenge.allSubSections;
    _currentSubSection = challenge.currentSubSection;
    _currentDistance = challenge.currentDistance;
    _activeRiverId = challenge.activeRiver?.id;

    if (riverChanged) {
      _displaySteps = (_currentDistance / _stepLengthKm).round();
    }
    
    notifyListeners();
  }

  void startStepListening() {
    // 启动实时监听
    if (Platform.isIOS) {
      _startHealthKitPolling();
    } else {
      _startPedometerListening();
    }
    
    // 同时启动一个定时器，每隔一段时间从 DB 刷新一次（配合后台任务）
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _updateUIFromDB());
  }

  void _startPedometerListening() {
    _pedometerSubscription = Pedometer.stepCountStream.listen((event) async {
      await StepSyncService.syncAndroidSensor();
      await _updateUIFromDB();
    });
  }

  void _startHealthKitPolling() {
    // iOS 依然采用轮询方式获取实时步数
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await StepSyncService.syncHealthData(days: 1);
      await _updateUIFromDB();
    });
  }

  Future<void> saveWeatherToDatabase() async {
    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
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
          aqi: _aqi,
        ));
      }
    } catch (e) {
      debugPrint("Weather DB Save Error: $e");
    }
  }

  Future<void> fetchWeather(double lat, double lon) async {
    _lat = lat;
    _lon = lon;
    // 1. 主天气请求：成功即更新 UI，不因 AQI/城市接口失败而整段失败（Android 常见单接口不可达）
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&timezone=auto');
      final res = await http.get(url);
      if (res.statusCode != 200) {
        debugPrint("Fetch weather HTTP ${res.statusCode}: ${res.body.length} bytes");
        return;
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      _temp = "${current['temperature_2m']}°";
      _apparentTemp = "${current['apparent_temperature']}°";
      _humidity = "${current['relative_humidity_2m']}%";
      _wmoCode = (current['weather_code'] as num).toInt();
      _windSpeed = (current['wind_speed_10m'] as num).toDouble();
      final daily = data['daily'] as Map<String, dynamic>;
      _maxTemp = "${(daily['temperature_2m_max'] as List)[0]}°";
      _minTemp = "${(daily['temperature_2m_min'] as List)[0]}°";

      _saveWeatherToCache();
      await saveWeatherToDatabase();
      notifyListeners();
    } catch (e, stack) {
      debugPrint("Fetch weather error: $e");
      if (kDebugMode) debugPrint("$stack");
      return;
    }

    // 2. AQI 可选：失败仅保留默认，不影响主天气展示
    try {
      final aqUrl = Uri.parse(
          'https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=european_aqi,pm2_5');
      final aqRes = await http.get(aqUrl);
      if (aqRes.statusCode == 200) {
        final aqData = json.decode(aqRes.body) as Map<String, dynamic>;
        final aqCurrent = aqData['current'] as Map<String, dynamic>;
        _aqi = aqCurrent['european_aqi'].toString();
        _pm2_5 = aqCurrent['pm2_5'].toString();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Fetch AQI error: $e");
    }

    // 3. 城市名可选：失败保留默认
    try {
      final cityUrl = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=zh');
      final cityRes = await http.get(cityUrl);
      if (cityRes.statusCode == 200) {
        final cityData = json.decode(cityRes.body) as Map<String, dynamic>;
        _cityName = cityData['city'] ?? "未知地点";
        _saveWeatherToCache();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Fetch city error: $e");
    }
  }

  Future<void> _loadCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString('cached_weather_v2');
    if (cached != null) {
      final data = json.decode(cached) as Map<String, dynamic>;
      _temp = data['temp'] ?? _temp;
      _cityName = data['city'] ?? _cityName;
      _wmoCode = (data['wmo_code'] as num?)?.toInt() ?? _wmoCode;
      _maxTemp = data['max_temp'] ?? _maxTemp;
      _minTemp = data['min_temp'] ?? _minTemp;
      final latNum = data['lat'];
      final lonNum = data['lon'];
      if (latNum != null && lonNum != null) {
        _lat = (latNum as num).toDouble();
        _lon = (lonNum as num).toDouble();
      }
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
    _refreshTimer?.cancel();
    super.dispose();
  }
}
