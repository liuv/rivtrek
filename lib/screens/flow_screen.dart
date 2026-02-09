import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/river_settings.dart';
import '../models/daily_stats.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

import 'dart:math' as math;

// --- 数据模型 ---
class Lantern {
  final double id;
  double localY; 
  final double randomX; 
  final double wobbleSpeed;
  final double wobblePhase;
  final double scaleBase;
  double rotation = 0;

  Lantern({
    required this.id,
    this.localY = -1.2,
    required this.randomX,
    required this.wobbleSpeed,
    required this.wobblePhase,
    required this.scaleBase,
  });
}

class Blessing {
  final String text;
  double localY;
  double opacity = 1.0;
  double blur = 0.0;
  final double randomX;

  Blessing({
    required this.text,
    required this.localY,
    required this.randomX,
  });
}

class RiverSection {
  final String name;
  final String themeColor;
  final List<SubSection> subSections;
  RiverSection.fromJson(Map<String, dynamic> json)
      : name = json['section_name'],
        themeColor = json['theme_color'],
        subSections = (json['sub_sections'] as List)
            .map((s) => SubSection.fromJson(s, json['theme_color']))
            .toList();
}

class SubSection {
  final String name;
  final double accumulatedLength;
  final double baseFlowSpeed;
  final int difficulty;
  final Color color;
  SubSection.fromJson(Map<String, dynamic> json, String defaultColor)
      : name = json['sub_section_name'],
        accumulatedLength = json['accumulated_length_km'].toDouble(),
        baseFlowSpeed = json['base_flow_speed'].toDouble(),
        difficulty = json['difficulty_rating'],
        color = Color(int.parse(defaultColor.replaceFirst('#', '0xFF')));
}

class FlowScreen extends StatefulWidget {
  const FlowScreen({super.key});
  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  ui.FragmentShader? _proceduralShader;
  ui.FragmentShader? _inkShader;
  ui.FragmentShader? _auroraShader;

  List<Offset> _riverPoints = []; // [lon, lat]
  List<double> _cumulativeDistances = [];
  List<double> _currentPathOffsets = List.filled(32, 0.0);
  final List<Lantern> _lanterns = [];
  final List<Blessing> _blessings = [];
  double _lastFrameTime = 0;

  late AnimationController _timeController;
  // 祭江特效相关
  late AnimationController _pulseController;
  Offset _pulseCenter = Offset.zero;

  // 节流，防止频繁写入数据库
  DateTime _lastDbSaveTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedSteps = 0;
  late AnimationController _distanceController;
  late Stopwatch _stopwatch;
  StreamSubscription? _pedometerSubscription;

  List<SubSection> _allSubSections = [];
  SubSection? _currentSubSection;
  double _currentDistance = 0.0;
  final double _stepLengthKm = 0.0007;

  final Set<int> _pointers = {};

  // 状态
  int _displaySteps = 0;
  bool _isUsingHealthPlugin = true;
  final Health health = Health();

  // 天气与定位状态
  String _temp = "--";
  String _maxTemp = "--";
  String _minTemp = "--";
  String _cityName = "待定位";
  WeatherType _weatherType = WeatherType.unknown;
  int _wmoCode = 0;
  String _coords = "无信号";
  double _windSpeed = 0.0;
  double _lat = 0.0;
  double _lon = 0.0;
  IconData _weatherIcon = Icons.wb_cloudy_outlined;

  // 缓存键名
  static const String _kLastWeatherTime = 'last_weather_time';
  static const String _kCachedWeather = 'cached_weather_data';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialSettings();
    _loadData();
    _loadShaders();
    _loadRealRiverPath();
    _stopwatch = Stopwatch()..start();
    _timeController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _timeController.addListener(() {
      if (mounted) {
        _updateLanterns();
        setState(() {});
      }
    });
    _timeController.repeat();
    _distanceController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    _timeController = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
    _timeController.addListener(() {
      if (mounted) {
        _updateLanterns();
        setState(() {});
      }
    });

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _pulseController.addListener(() {
      if (mounted) setState(() {});
    });

    _initPermissionsSequentially();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveToDatabase(force: true); // 销毁前强制保存
    _timeController.dispose();
    _distanceController.dispose();
    _pulseController.dispose();
    _pedometerSubscription?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 当应用进入后台，强制保存一次数据
      _saveToDatabase(force: true);
      // 停止动画和秒表以节省 CPU 和电量
      _timeController.stop();
      _stopwatch.stop();
    } else if (state == AppLifecycleState.resumed) {
      // 当应用回到前台，恢复动画和秒表
      if (mounted) {
        _timeController.repeat();
        _stopwatch.start();
        // 回到前台时顺便检查一下天气是否需要更新
        _initWeatherWithGeolocator();
      }
    }
  }

  void _initPermissionsSequentially() async {
    await _initHybridSync();
    await _loadCachedWeather(); // 先加载缓存
    _initWeatherWithGeolocator();
  }

  Future<void> _loadCachedWeather() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString(_kCachedWeather);
      if (cachedData != null && mounted) {
        final data = json.decode(cachedData);
        setState(() {
          _temp = data['temp'] ?? "--";
          _maxTemp = data['max_temp'] ?? "--";
          _minTemp = data['min_temp'] ?? "--";
          _cityName = data['city'] ?? "待定位";
          _wmoCode = data['wmo_code'] ?? 0;
          _weatherType = _mapWeatherCode(_wmoCode);
          _coords = data['coords'] ?? "无信号";
          _windSpeed = (data['wind_speed'] ?? 0.0).toDouble();
          _lat = data['lat'] ?? 0.0;
          _lon = data['lon'] ?? 0.0;
          _weatherIcon = _weatherType.icon;
        });
      }
    } catch (e) {
      debugPrint("Error loading cached weather: $e");
    }
  }

  bool _shouldUpdateWeather(SharedPreferences prefs) {
    final int? lastTime = prefs.getInt(_kLastWeatherTime);
    if (lastTime == null) return true;

    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastTime);
    final now = DateTime.now();

    // 如果不是同一天，更新
    if (lastDate.year != now.year ||
        lastDate.month != now.month ||
        lastDate.day != now.day) {
      return true;
    }

    // 如果超过8小时，更新
    final difference = now.difference(lastDate).inHours;
    if (difference >= 8) {
      return true;
    }

    return false;
  }

  void _initWeatherWithGeolocator() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查是否需要更新
      if (!_shouldUpdateWeather(prefs) && _cityName != "待定位") {
        debugPrint("Using cached weather data, skipping fetch.");
        return;
      }

      if (!mounted) return;
      setState(() => _cityName = _cityName == "待定位" ? "检查权限..." : _cityName);

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && _cityName == "检查权限...") {
          setState(() => _cityName = "GPS未开启");
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw "权限被拒绝";
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted && _cityName == "检查权限...") {
          setState(() => _cityName = "权限已封死");
          _showManualPermissionHint();
        }
        return;
      }

      if (mounted) {
        setState(() => _cityName = _cityName == "检查权限..." || _cityName == "待定位"
            ? "定位中..."
            : _cityName);
      }

      // 优化：先尝试获取最后一次已知位置，提高速度
      Position? position = await Geolocator.getLastKnownPosition();

      // 如果没有最后已知位置，或者位置太旧，则获取当前位置
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, // 提高到中等精度
            timeLimit: Duration(seconds: 8),
          ),
        ).timeout(const Duration(seconds: 10));
      }

      final double lat = position.latitude;
      final double lon = position.longitude;

      if (mounted) {
        setState(() {
          _lat = lat;
          _lon = lon;
          _coords = "${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}";
          if (_cityName == "定位中...") _cityName = "查询中...";
        });
      }

      // 并发获取城市名和天气
      await Future.wait([
        _fetchCityNameWeb(lat, lon),
        _fetchWeather(lat, lon, prefs),
      ]);
    } catch (e) {
      debugPrint("Geolocator Logic Error: $e");
      if (mounted && (_cityName == "定位中..." || _cityName == "检查权限...")) {
        setState(() => _cityName = "定位偏差");
        _fetchDefaultWeather();
      }
    }
  }

  void _showManualPermissionHint() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("定位权限已被永久禁用，请在设置中开启"),
      action: SnackBarAction(
          label: "去设置", onPressed: () => Geolocator.openAppSettings()),
    ));
  }

  Future<void> _fetchWeather(
      double lat, double lon, SharedPreferences prefs) async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=temperature_2m_max,temperature_2m_min&timezone=auto');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final daily = data['daily'];

        final int iconCode = current['weathercode'];
        final String temp = "${current['temperature'].round()}°";
        final String maxT = "${daily['temperature_2m_max'][0].round()}°";
        final String minT = "${daily['temperature_2m_min'][0].round()}°";
        final double windSpeed = current['windspeed'].toDouble();
        final WeatherType type = _mapWeatherCode(iconCode);

        if (mounted) {
          setState(() {
            _temp = temp;
            _maxTemp = maxT;
            _minTemp = minT;
            _windSpeed = windSpeed;
            _wmoCode = iconCode;
            _weatherType = type;
            _weatherIcon = type.icon;
          });

          // 缓存数据
          _saveWeatherToCache(prefs, temp, maxT, minT, iconCode, windSpeed);
          _saveToDatabase();
        }
      }
    } catch (e) {
      debugPrint("Weather Fetch Error: $e");
    }
  }

  WeatherType _mapWeatherCode(int code) {
    if (code == 0) return WeatherType.clearSky;
    if (code == 1) return WeatherType.mainlyClear;
    if (code == 2) return WeatherType.partlyCloudy;
    if (code == 3) return WeatherType.overcast;
    if (code == 45 || code == 48) return WeatherType.fog;
    if (code == 51 || code == 53 || code == 55) return WeatherType.drizzle;
    if (code == 56 || code == 57) return WeatherType.freezingDrizzle;
    if (code == 61) return WeatherType.rainSlight;
    if (code == 63) return WeatherType.rainModerate;
    if (code == 65) return WeatherType.rainHeavy;
    if (code == 66 || code == 67) return WeatherType.freezingRain;
    if (code == 71) return WeatherType.snowSlight;
    if (code == 73) return WeatherType.snowModerate;
    if (code == 75) return WeatherType.snowHeavy;
    if (code == 77) return WeatherType.snowGrains;
    if (code >= 80 && code <= 82) return WeatherType.rainShowers;
    if (code == 85 || code == 86) return WeatherType.snowShowers;
    if (code == 95) return WeatherType.thunderstorm;
    if (code >= 96) return WeatherType.thunderstormHail;
    return WeatherType.unknown;
  }

  void _saveWeatherToCache(SharedPreferences prefs, String temp, String maxT,
      String minT, int wmoCode, double windSpeed) {
    final weatherData = {
      'temp': temp,
      'max_temp': maxT,
      'min_temp': minT,
      'city': _cityName,
      'wmo_code': wmoCode,
      'coords': _coords,
      'wind_speed': windSpeed,
      'lat': _lat,
      'lon': _lon,
      'last_update': DateTime.now().millisecondsSinceEpoch,
    };
    prefs.setString(_kCachedWeather, json.encode(weatherData));
    prefs.setInt(_kLastWeatherTime, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _saveToDatabase({bool force = false}) async {
    // 如果不是强制保存，则检查步数变化是否显著（例如超过500步）
    if (!force && (_displaySteps - _lastSavedSteps).abs() < 500) {
      return;
    }

    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. 保存活动数据 (步数、里程)
      final activity = DailyActivity(
        date: date,
        steps: _displaySteps,
        distanceKm: _displaySteps * _stepLengthKm,
        accumulatedDistanceKm: _currentDistance,
      );
      await DatabaseService.instance.saveActivity(activity);
      _lastSavedSteps = _displaySteps;

      // 2. 保存天气数据 (只有在天气已获取的情况下)
      if (_wmoCode != 0) {
        final weather = DailyWeather(
          date: date,
          wmoCode: _wmoCode,
          currentTemp: _temp,
          maxTemp: _maxTemp,
          minTemp: _minTemp,
          windSpeed: _windSpeed,
          cityName: _cityName,
          latitude: _lat,
          longitude: _lon,
        );
        await DatabaseService.instance.saveWeather(weather);
      }

      debugPrint("Daily data synced to DB for $date");
    } catch (e) {
      debugPrint("DB Save Error: $e");
    }
  }

  Future<void> _fetchCityNameWeb(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=zh');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String city = data['city'] ??
            data['locality'] ??
            data['principalSubdivision'] ??
            "";
        if (city.isNotEmpty && mounted) {
          setState(() => _cityName = city);

          // 更新缓存中的城市名
          final prefs = await SharedPreferences.getInstance();
          final String? cachedData = prefs.getString(_kCachedWeather);
          if (cachedData != null) {
            final Map<String, dynamic> weatherMap = json.decode(cachedData);
            weatherMap['city'] = city;
            prefs.setString(_kCachedWeather, json.encode(weatherMap));
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
    }
    if (mounted && (_cityName == "查询中..." || _cityName == "定位中...")) {
      setState(() => _cityName = "${lat.toStringAsFixed(1)}°N");
    }
  }

  void _fetchDefaultWeather() async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=38.91&longitude=121.61&current_weather=true&daily=temperature_2m_max,temperature_2m_min&timezone=auto');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final daily = data['daily'];
        if (mounted) {
          setState(() {
            _temp = "${current['temperature'].round()}°";
            _maxTemp = "${daily['temperature_2m_max'][0].round()}°";
            _minTemp = "${daily['temperature_2m_min'][0].round()}°";
            _wmoCode = current['weathercode'];
            _weatherType = _mapWeatherCode(_wmoCode);
            _weatherIcon = _weatherType.icon;
          });
        }
      }
    } catch (_) {}
  }

  void _showWeatherDetail() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("当前位置与天气",
            style: TextStyle(fontWeight: FontWeight.w300)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("位置: $_cityName",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
            Text("坐标: $_coords",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("当前温度: $_temp", style: const TextStyle(fontSize: 16)),
                Text("状态: ${_weatherType.label}",
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text("今日温差: $_minTemp ~ $_maxTemp",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text("当前风速: ${_windSpeed.toStringAsFixed(1)} km/h",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text(
                "同步时间: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                style: const TextStyle(fontSize: 14, color: Colors.cyan)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("确定"))
        ],
      ),
    );
  }

  Future<void> _initHybridSync() async {
    await [Permission.activityRecognition].request();
    bool healthReady = await _trySyncWithHealth();
    if (!healthReady) {
      _isUsingHealthPlugin = false;
      _startPedometerStream();
    }
  }

  Future<bool> _trySyncWithHealth() async {
    try {
      var types = [HealthDataType.STEPS];
      bool requested = await health.requestAuthorization(types);
      if (!requested) return false;
      DateTime now = DateTime.now();
      DateTime midnight = DateTime(now.year, now.month, now.day);
      int? steps = await health.getTotalStepsInInterval(midnight, now);
      if (steps != null && steps > 0 && mounted) {
        setState(() {
          _displaySteps = steps;
          _animateToDistance(steps * _stepLengthKm);
        });
        _saveToDatabase(force: true); // 初始获取步数后强制保存一次
        return true;
      }
    } catch (e) {
      debugPrint("Health Sync Failed: $e");
    }
    return false;
  }

  void _startPedometerStream() {
    _pedometerSubscription = Pedometer.stepCountStream.listen((event) async {
      final prefs = await SharedPreferences.getInstance();
      final String today = DateTime.now().toString().split(' ')[0];
      int hardwareTotal = event.steps;
      String? lastDate = prefs.getString('last_sync_date');
      int base = prefs.getInt('base_steps_value') ?? hardwareTotal;
      if (lastDate != today || hardwareTotal < base) {
        await prefs.setString('last_sync_date', today);
        await prefs.setInt('base_steps_value', hardwareTotal);
        base = hardwareTotal;
      }
      int stepsToday = hardwareTotal - base;
      if (mounted) {
        setState(() {
          _displaySteps = stepsToday;
          _animateToDistance(stepsToday * _stepLengthKm);
        });
      }
    });
    _pedometerSubscription?.onError((e) => debugPrint("Pedometer Error: $e"));
  }

  void _animateToDistance(double target) {
    if ((target - _currentDistance).abs() < 0.001) return;
    final anim = Tween<double>(begin: _currentDistance, end: target).animate(
        CurvedAnimation(
            parent: _distanceController, curve: Curves.easeInOutCubic));
    anim.addListener(() => _updateCurrentProgress(anim.value));
    _distanceController.reset();
    _distanceController.forward();
  }

  Future<void> _loadData() async {
    try {
      final String response =
          await rootBundle.loadString('assets/json/rivers/yangtze_master.json');
      final data = json.decode(response);
      List<SubSection> flatList = [];
      for (var s in data['challenge_sections']) {
        flatList.addAll(RiverSection.fromJson(s).subSections);
      }
      if (mounted) {
        setState(() {
          _allSubSections = flatList;
          _updateCurrentProgress(_currentDistance);
        });
      }
    } catch (e) {
      debugPrint("Data load error: $e");
    }
  }

  Future<void> _loadInitialSettings() async {
    final prefs = await SharedPreferences.getInstance();
    RiverSettings.instance.update(
      pathMode: RiverPathMode.values[prefs.getInt('river_path_mode') ?? 0],
      style: RiverStyle.values[prefs.getInt('river_style') ?? 0],
      speed: prefs.getDouble('river_speed') ?? 0.3,
      turbulence: prefs.getDouble('river_turbulence') ?? 0.6,
      width: prefs.getDouble('river_width') ?? 0.18,
    );
  }

  Future<void> _loadShaders() async {
    try {
      final p1 = await ui.FragmentProgram.fromAsset('shaders/river.frag');
      final p2 = await ui.FragmentProgram.fromAsset('shaders/river_ink.frag');
      final p4 =
          await ui.FragmentProgram.fromAsset('shaders/river_aurora.frag');
      if (mounted) {
        setState(() {
          _proceduralShader = p1.fragmentShader();
          _inkShader = p2.fragmentShader();
          _auroraShader = p4.fragmentShader();
        });
      }
    } catch (e) {
      debugPrint("Shader error: $e");
    }
  }

  Future<void> _loadRealRiverPath() async {
    try {
      final String response =
          await rootBundle.loadString('assets/json/rivers/yangtze_points.json');
      final data = json.decode(response);
      final List sections = data['sections_points'];

      List<Offset> allPoints = [];
      for (var section in sections) {
        for (var point in section) {
          allPoints.add(Offset(point[0].toDouble(), point[1].toDouble()));
        }
      }

      // 计算累计里程
      List<double> distances = [0.0];
      double totalDist = 0.0;
      for (int i = 1; i < allPoints.length; i++) {
        totalDist += Geolocator.distanceBetween(allPoints[i - 1].dy,
                allPoints[i - 1].dx, allPoints[i].dy, allPoints[i].dx) /
            1000.0; // km
        distances.add(totalDist);
      }

      if (mounted) {
        setState(() {
          _riverPoints = allPoints;
          _cumulativeDistances = distances;
        });
        _updatePathOffsets(_currentDistance);
      }
    } catch (e) {
      debugPrint("Real path load error: $e");
    }
  }

  void _updatePathOffsets(double distance) {
    if (_riverPoints.isEmpty || _cumulativeDistances.isEmpty) return;

    // 找到当前距离对应的索引
    int centerIdx = _findDistanceIndex(distance);

    // 我们想要显示当前里程前后约 10km 的路径
    double windowKm = 10.0;
    List<double> offsets = [];

    // 采样32个点
    for (int i = 0; i < 32; i++) {
      double targetDist = distance + (i / 31.0 - 0.5) * windowKm * 2;
      int idx = _findDistanceIndex(targetDist);
      offsets.add(_calculateRelativeOffset(idx, centerIdx));
    }

    setState(() {
      _currentPathOffsets = offsets;
    });
  }

  int _findDistanceIndex(double dist) {
    if (dist <= 0) return 0;
    if (dist >= _cumulativeDistances.last)
      return _cumulativeDistances.length - 1;

    // 二分查找
    int low = 0, high = _cumulativeDistances.length - 1;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      if (_cumulativeDistances[mid] < dist) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  double _calculateRelativeOffset(int idx, int centerIdx) {
    // 简单的相对经度偏移作为曲线模拟（在小范围内经度变化可近似为水平偏移）
    // 为了让效果更明显，我们乘以一个放大系数
    return (_riverPoints[idx].dx - _riverPoints[centerIdx].dx) * 10.0;
  }

  void _updateLanterns() {
    final double currentTime = _stopwatch.elapsedMilliseconds / 1000.0;
    if (_lastFrameTime == 0) {
      _lastFrameTime = currentTime;
      return;
    }
    final double dt = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    final settings = RiverSettings.instance;
    final sub = _currentSubSection!;
    final double currentSpeed =
        (settings.speed + (sub.baseFlowSpeed * 0.1)) * 0.5;

    // 更新河灯
    for (int i = _lanterns.length - 1; i >= 0; i--) {
      final lantern = _lanterns[i];
      lantern.localY += currentSpeed * dt;
      double combinedWobbleSpeed = lantern.wobbleSpeed * (1.0 + currentSpeed * 2.0);
      double noise = math.sin(currentTime * combinedWobbleSpeed + lantern.wobblePhase) * 0.7
                   + math.sin(currentTime * combinedWobbleSpeed * 2.1 + lantern.wobblePhase * 1.3) * 0.3;
      double speedFactor = (currentSpeed * 4.0).clamp(0.4, 1.2);
      lantern.rotation = noise * (math.pi / 4) * speedFactor;
      if (lantern.localY > 1.2) _lanterns.removeAt(i);
    }

    // 更新祈福文字
    for (int i = _blessings.length - 1; i >= 0; i--) {
      final b = _blessings[i];
      b.localY += currentSpeed * 0.8 * dt; // 文字漂得慢一点
      b.opacity = (b.opacity - 0.15 * dt).clamp(0.0, 1.0); // 减慢消失速度 (从0.25改为0.15)
      b.blur += 2.0 * dt; // 减慢模糊速度 (从5.0改为2.0)
      if (b.opacity <= 0) _blessings.removeAt(i);
    }
  }

  void _addBlessing(Offset position) {
    final List<String> words = ["安", "顺", "福", "宁", "和"];
    final Size size = MediaQuery.of(context).size;
    
    setState(() {
      _pulseCenter = Offset(position.dx / size.width, position.dy / size.height);
      _blessings.add(Blessing(
        text: words[math.Random().nextInt(words.length)],
        localY: (position.dy / size.height) * 2.0 - 1.0,
        randomX: (math.Random().nextDouble() - 0.5) * 0.05,
      ));
    });
    
    _pulseController.reset();
    _pulseController.forward();
    _recordRitualEvent();
  }

  Future<void> _recordRitualEvent() async {
    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await DatabaseService.instance.recordEvent(RiverEvent(
        date: date,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: RiverEventType.activity,
        name: "祭江祈福",
        description: "在 ${_currentSubSection?.name} 举行祭江仪式",
        latitude: _lat,
        longitude: _lon,
        distanceAtKm: _currentDistance,
      ));
    } catch (e) {
      debugPrint("Record ritual event error: $e");
    }
  }

  void _addLantern() {
    setState(() {
      _lanterns.add(Lantern(
        id: DateTime.now().millisecondsSinceEpoch.toDouble(),
        randomX: (math.Random().nextDouble() - 0.5) * 0.1,
        wobbleSpeed: 1.5 + math.Random().nextDouble() * 1.5,
        wobblePhase: math.Random().nextDouble() * math.pi * 2,
        scaleBase: 0.8 + math.Random().nextDouble() * 0.4,
      ));
    });

    // 记录到数据库作为事件
    _recordLanternEvent();
  }

  Future<void> _recordLanternEvent() async {
    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await DatabaseService.instance.recordEvent(RiverEvent(
        date: date,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: RiverEventType.activity,
        name: "放河灯",
        description: "在 ${_currentSubSection?.name} 放下一盏河灯",
        latitude: _lat,
        longitude: _lon,
        distanceAtKm: _currentDistance,
      ));
    } catch (e) {
      debugPrint("Record lantern event error: $e");
    }
  }

  double _getRiverPathAt(double py, RiverSettings settings, SubSection sub) {
    final double scrollY = py + (_currentDistance / 10.0) * 2.0;
    final double turbulence = settings.turbulence + (sub.difficulty * 0.1);

    double path;
    if (settings.pathMode == RiverPathMode.realPath &&
        _riverPoints.isNotEmpty) {
      // 真实路径插值
      double idx = (py * 0.5 + 0.5) * 31.0;
      int i = idx.floor().clamp(0, 31);
      int j = (i + 1).clamp(0, 31);
      double f = idx - i;
      path = math.max(
              -1.0,
              math.min(
                  1.0,
                  _currentPathOffsets[i] * (1 - f) +
                      _currentPathOffsets[j] * f)) *
          0.5;
    } else {
      // 程序化路径公式
      path = math.sin(scrollY * 1.5) * 0.25;
    }
    path += math.cos(scrollY * 3.5) * 0.05 * turbulence;
    return path;
  }

  void _updateCurrentProgress(double distance) {
    if (!mounted) return;
    _currentDistance = distance.clamp(0.0, 6387.0);

    // 更新路径偏移
    if (RiverSettings.instance.pathMode == RiverPathMode.realPath) {
      _updatePathOffsets(_currentDistance);
    }

    SubSection? found;
    for (var sub in _allSubSections) {
      if (_currentDistance <= sub.accumulatedLength) {
        found = sub;
        break;
      }
    }
    setState(() {
      _currentSubSection =
          found ?? (_allSubSections.isNotEmpty ? _allSubSections.last : null);
    });

    // 只有在步数变化显著时才会触发保存（内部逻辑控制）
    _saveToDatabase();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_allSubSections.isEmpty || _proceduralShader == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final sub = _currentSubSection!;

    return ListenableBuilder(
      listenable: RiverSettings.instance,
      builder: (context, _) {
        final settings = RiverSettings.instance;
        ui.FragmentShader currentShader;
        switch (settings.style) {
          case RiverStyle.classic:
            currentShader = _proceduralShader!;
            break;
          case RiverStyle.ink:
            currentShader = _inkShader ?? _proceduralShader!;
            break;
          case RiverStyle.aurora:
            currentShader = _auroraShader ?? _proceduralShader!;
            break;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            onDoubleTap: _addLantern,
            onLongPressStart: (details) => _addBlessing(details.localPosition),
            child: Listener(
                onPointerDown: (e) => setState(() => _pointers.add(e.pointer)),
                onPointerUp: (e) => setState(() => _pointers.remove(e.pointer)),
                onPointerCancel: (e) =>
                    setState(() => _pointers.remove(e.pointer)),
                onPointerMove: (event) {
                  if (_pointers.length == 2) {
                    double sensitivity = 1.0;
                    _updateCurrentProgress(
                        _currentDistance - (event.delta.dy * sensitivity));
                  }
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: RiverShaderPainter(
                          shader: currentShader,
                          useRealPath:
                              settings.pathMode == RiverPathMode.realPath,
                          pathOffsets: _currentPathOffsets,
                          time: _stopwatch.elapsedMilliseconds / 1000.0,
                          turbulence:
                              settings.turbulence + (sub.difficulty * 0.1),
                          width: settings.width + (sub.baseFlowSpeed * 0.02),
                          speed: settings.speed + (sub.baseFlowSpeed * 0.1),
                          themeColor: sub.color,
                          offset: _currentDistance / 10.0,
                          pulse: _pulseController.value,
                          pulseX: _pulseCenter.dx,
                          pulseY: _pulseCenter.dy,
                        ),
                      ),
                    ),
                    // 祈福文字渲染层
                    ..._blessings.map((b) {
                      final double pathX =
                          _getRiverPathAt(b.localY, settings, sub);
                      final Size screenSize = MediaQuery.of(context).size;
                      final double aspect =
                          screenSize.width / screenSize.height;
                      final double screenX = (pathX + b.randomX) / aspect;
                      final double x = (screenX * 0.5 + 0.5) * screenSize.width;
                      final double y =
                          (b.localY * 0.5 + 0.5) * screenSize.height;

                      return Positioned(
                        left: x - 20,
                        top: y - 40,
                        child: Opacity(
                          opacity: b.opacity,
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                                sigmaX: b.blur, sigmaY: b.blur),
                            child: Text(
                              b.text,
                              style: const TextStyle(
                                fontSize: 52, // 稍微加大字号
                                color: Color(0xFFFFD700), // 纯正金色
                                fontWeight: FontWeight.w600, // 加粗，更有书法力道
                                fontFamily: 'Serif', 
                                shadows: [
                                  Shadow(
                                      color: Colors.orangeAccent,
                                      blurRadius: 15,
                                      offset: Offset(0, 0)),
                                  Shadow(
                                      color: Colors.black45,
                                      blurRadius: 5,
                                      offset: Offset(2, 2)), // 增加一个深色底影，提升对比度
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    // 河灯渲染层
                    ..._lanterns.map((l) {
                      final double pathX =
                          _getRiverPathAt(l.localY, settings, sub);
                      final Size screenSize = MediaQuery.of(context).size;
                      final double aspect =
                          screenSize.width / screenSize.height;

                      // 将 GL 坐标 (-1, 1) 映射到屏幕坐标
                      // 注意 GL 的 X 是经过 aspect 缩放的：p.x *= res.x / res.y;
                      final double screenX = (pathX + l.randomX) / aspect;
                      final double x = (screenX * 0.5 + 0.5) * screenSize.width;
                      final double y =
                          (l.localY * 0.5 + 0.5) * screenSize.height;

                      // 拟真缩放：越往下（越近）越大
                      final double scale =
                          l.scaleBase * (0.8 + (l.localY + 1.0) * 0.2);

                      return Positioned(
                        left: x - 25, // 图片中心对齐
                        top: y - 25,
                        child: Transform.rotate(
                          angle: l.rotation,
                          child: Opacity(
                            // 边缘淡入淡出
                            opacity: (1.0 -
                                (l.localY.abs() - 0.8).clamp(0.0, 0.2) / 0.2),
                            child: Image.asset(
                              'assets/icons/light01.png',
                              width: 50 * scale,
                              height: 50 * scale,
                              // 叠加辉光效果（在极光模式下更明显）
                              color: settings.style == RiverStyle.aurora
                                  ? Colors.white.withOpacity(0.9)
                                  : null,
                              colorBlendMode:
                                  settings.style == RiverStyle.aurora
                                      ? BlendMode.plus
                                      : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    SafeArea(
                        child: Column(children: [
                      const SizedBox(height: 25),
                      _buildHeader(sub),
                      const Spacer(flex: 3),
                      _buildStepsAndProgress(),
                      const Spacer(flex: 4),
                    ])),
                    Positioned(
                        top: 50,
                        right: 20,
                        child: Icon(
                          _isUsingHealthPlugin
                              ? Icons.health_and_safety
                              : Icons.directions_walk,
                          color: Colors.black26,
                          size: 16,
                        )),
                  ],
                ),
              ),
            ),
          );
        });
  }

  Widget _buildHeader(SubSection sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 45),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(sub.name.split('·')[0],
              style: const TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 18,
                  fontWeight: FontWeight.w400)),
          GestureDetector(
            onTap: _showWeatherDetail,
            child: Row(children: [
              Text(_temp,
                  style: const TextStyle(
                      color: Color(0xFF222222),
                      fontSize: 18,
                      fontWeight: FontWeight.w300)),
              const SizedBox(width: 8),
              Icon(_weatherIcon, size: 22, color: const Color(0xFF222222)),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        Text(sub.name,
            style: TextStyle(
                color: const Color(0xFF222222).withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w300)),
      ]),
    );
  }

  Widget _buildStepsAndProgress() {
    String stepsStr = _displaySteps.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    double fontSize = stepsStr.length > 7 ? 82 : 105;
    return Column(children: [
      Text(stepsStr,
          style: TextStyle(
              color: const Color(0xFF222222),
              fontSize: fontSize,
              fontWeight: FontWeight.w100,
              letterSpacing: -2)),
      const SizedBox(height: 5),
      Text("已行至 ${_currentDistance.toStringAsFixed(1)} km / 6387 km",
          style: TextStyle(
              color: const Color(0xFF555555).withOpacity(0.7),
              fontSize: 16,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2)),
    ]);
  }
}

class RiverShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final bool useRealPath;
  final List<double> pathOffsets;
  final double time;
  final double turbulence;
  final double width;
  final double speed;
  final Color themeColor;
  final double offset;
  final double pulse;
  final double pulseX;
  final double pulseY;
  RiverShaderPainter(
      {required this.shader,
      required this.useRealPath,
      required this.pathOffsets,
      required this.time,
      required this.turbulence,
      required this.width,
      required this.speed,
      required this.themeColor,
      required this.offset,
      required this.pulse,
      required this.pulseX,
      required this.pulseY});
  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, time);
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);
    shader.setFloat(3, speed);
    shader.setFloat(4, turbulence);
    shader.setFloat(5, width);
    shader.setFloat(6, themeColor.red / 255.0);
    shader.setFloat(7, themeColor.green / 255.0);
    shader.setFloat(8, themeColor.blue / 255.0);
    shader.setFloat(9, offset);
    shader.setFloat(10, useRealPath ? 1.0 : 0.0);
    
    // 路径数据 (11-42)
    for (int i = 0; i < 32; i++) {
      shader.setFloat(11 + i, pathOffsets[i]);
    }

    // 脉冲数据
    shader.setFloat(43, pulse);
    shader.setFloat(44, pulseX);
    shader.setFloat(45, pulseY);
    
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant RiverShaderPainter oldDelegate) => true;
}
