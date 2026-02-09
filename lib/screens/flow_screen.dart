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

// --- 数据模型 ---
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

class _FlowScreenState extends State<FlowScreen> with TickerProviderStateMixin, WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  ui.FragmentShader? _shader;
  late AnimationController _timeController;
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
  String _cityName = "待定位";
  String _weatherDesc = "未知";
  String _coords = "无信号";
  IconData _weatherIcon = Icons.wb_cloudy_outlined;

  // 缓存键名
  static const String _kLastWeatherTime = 'last_weather_time';
  static const String _kCachedWeather = 'cached_weather_data';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _loadShader();
    _stopwatch = Stopwatch()..start();
    _timeController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _timeController.addListener(() {
      if (mounted) setState(() {});
    });
    _timeController.repeat();
    _distanceController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    _initPermissionsSequentially();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeController.dispose();
    _distanceController.dispose();
    _pedometerSubscription?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 当应用进入后台，停止动画和秒表以节省 CPU 和电量
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
          _cityName = data['city'] ?? "待定位";
          _weatherDesc = data['desc'] ?? "未知";
          _coords = data['coords'] ?? "无信号";
          _weatherIcon = _getWeatherIcon(data['icon_code'] ?? 0);
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
        setState(() => _cityName = _cityName == "检查权限..." || _cityName == "待定位" ? "定位中..." : _cityName);
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

  Future<void> _fetchWeather(double lat, double lon, SharedPreferences prefs) async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&timezone=auto');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final int iconCode = current['weathercode'];
        final String temp = "${current['temperature'].round()}°";
        final String desc = _getWeatherDesc(iconCode);

        if (mounted) {
          setState(() {
            _temp = temp;
            _weatherIcon = _getWeatherIcon(iconCode);
            _weatherDesc = desc;
          });
          
          // 缓存数据
          _saveWeatherToCache(prefs, temp, desc, iconCode);
        }
      }
    } catch (e) {
      debugPrint("Weather Fetch Error: $e");
    }
  }

  void _saveWeatherToCache(SharedPreferences prefs, String temp, String desc, int iconCode) {
    final weatherData = {
      'temp': temp,
      'city': _cityName,
      'desc': desc,
      'coords': _coords,
      'icon_code': iconCode,
      'last_update': DateTime.now().millisecondsSinceEpoch,
    };
    prefs.setString(_kCachedWeather, json.encode(weatherData));
    prefs.setInt(_kLastWeatherTime, DateTime.now().millisecondsSinceEpoch);
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
          'https://api.open-meteo.com/v1/forecast?latitude=38.91&longitude=121.61&current_weather=true&timezone=auto');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        if (mounted) {
          setState(() {
            _temp = "${current['temperature'].round()}°";
            _weatherIcon = _getWeatherIcon(current['weathercode']);
            _weatherDesc = _getWeatherDesc(current['weathercode']);
          });
        }
      }
    } catch (_) {}
  }

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code < 3) return Icons.wb_cloudy_outlined;
    if (code < 40) return Icons.cloud_queue_outlined;
    if (code < 70) return Icons.umbrella_outlined;
    return Icons.ac_unit_outlined;
  }

  String _getWeatherDesc(int code) {
    if (code == 0) return "晴朗";
    if (code <= 3) return "多云";
    if (code <= 48) return "雾";
    if (code <= 57) return "毛毛雨";
    if (code <= 67) return "阵雨";
    if (code <= 77) return "雪";
    if (code <= 82) return "大雨";
    if (code <= 86) return "阵雪";
    if (code <= 99) return "雷暴";
    return "未知";
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
            Text("温度: $_temp", style: const TextStyle(fontSize: 18)),
            Text("状态: $_weatherDesc", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text(
                "时间: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
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

  void _updateCurrentProgress(double distance) {
    if (!mounted) return;
    _currentDistance = distance.clamp(0.0, 6387.0);
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
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/river.frag');
      if (mounted) {
        setState(() => _shader = program.fragmentShader());
      }
    } catch (e) {
      debugPrint("Shader error: $e");
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_allSubSections.isEmpty || _shader == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final sub = _currentSubSection!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerDown: (e) => setState(() => _pointers.add(e.pointer)),
        onPointerUp: (e) => setState(() => _pointers.remove(e.pointer)),
        onPointerCancel: (e) => setState(() => _pointers.remove(e.pointer)),
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
                  shader: _shader!,
                  time: _stopwatch.elapsedMilliseconds / 1000.0,
                  turbulence: 0.5 + (sub.difficulty * 0.4),
                  width: 0.16 + (sub.baseFlowSpeed * 0.04),
                  speed: 0.2 + (sub.baseFlowSpeed * 0.2),
                  themeColor: sub.color,
                  offset: _currentDistance / 10.0,
                ),
              ),
            ),
            SafeArea(
                child: Column(children: [
              const SizedBox(height: 25),
              _buildHeader(sub),
              const Spacer(flex: 3),
              _buildStepsAndProgress(),
              const Spacer(flex: 4),
            ])),
            // 同步状态指示器
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
    );
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
  final double time;
  final double turbulence;
  final double width;
  final double speed;
  final Color themeColor;
  final double offset;
  RiverShaderPainter(
      {required this.shader,
      required this.time,
      required this.turbulence,
      required this.width,
      required this.speed,
      required this.themeColor,
      required this.offset});
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
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant RiverShaderPainter oldDelegate) => true;
}
