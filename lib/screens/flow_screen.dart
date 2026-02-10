import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/river_settings.dart';
import '../models/daily_stats.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/flow_models.dart';
import '../controllers/flow_controller.dart';
import '../providers/challenge_provider.dart';
import '../models/river_section.dart';
import 'river_selector_sheet.dart';

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
  
  // 渲染专用
  ui.FragmentShader? _proceduralShader;
  ui.FragmentShader? _inkShader;
  ui.FragmentShader? _auroraShader;

  List<Offset> _riverPoints = [];
  List<double> _cumulativeDistances = [];
  List<double> _currentPathOffsets = List.filled(32, 0.0);
  String? _loadedPointsRiverId;
  
  final List<Lantern> _lanterns = [];
  final List<Blessing> _blessings = [];
  double _lastFrameTime = 0;

  late AnimationController _timeController;
  late AnimationController _pulseController;
  Offset _pulseCenter = Offset.zero;

  late Stopwatch _stopwatch;
  final Set<int> _pointers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _timeController = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
    _timeController.addListener(() {
      if (mounted) {
        _updateFrame();
        setState(() {});
      }
    });

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _pulseController.addListener(() {
      if (mounted) setState(() {});
    });

    _stopwatch = Stopwatch()..start();
    
    // 初始化 Controller 并刷新天气
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<FlowController>();
      controller.init();
      controller.startStepListening();
      _refreshWeather();
    });
    
    _loadShaders();
  }

  void _updateFrame() {
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    
    // 检查是否需要切换路径数据
    if (challenge.activeRiver != null && _loadedPointsRiverId != challenge.activeRiver!.id) {
      _loadRealRiverPath(challenge.activeRiver!.pointsJsonPath, challenge.activeRiver!.id);
    }

    _updateLanterns(controller.currentSubSection);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeController.dispose();
    _pulseController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = context.read<FlowController>();
    if (state == AppLifecycleState.paused) {
      controller.saveToDatabase(force: true);
      _timeController.stop();
      _stopwatch.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _timeController.repeat();
        _stopwatch.start();
        _refreshWeather();
      }
    }
  }

  Future<void> _refreshWeather() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          context.read<FlowController>().fetchWeather(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {}
  }

  void _updateLanterns(SubSection? sub) {
    final double currentTime = _stopwatch.elapsedMilliseconds / 1000.0;
    if (_lastFrameTime == 0) {
      _lastFrameTime = currentTime;
      return;
    }
    final double dt = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    if (sub == null) return;

    final double currentSpeed = (RiverSettings.instance.speed + (sub.baseFlowSpeed * 0.1)) * 0.5;

    for (int i = _lanterns.length - 1; i >= 0; i--) {
      final l = _lanterns[i];
      l.localY += currentSpeed * dt;
      double combinedWobbleSpeed = l.wobbleSpeed * (1.0 + currentSpeed * 2.0);
      double noise = math.sin(currentTime * combinedWobbleSpeed + l.wobblePhase) * 0.7
                   + math.sin(currentTime * combinedWobbleSpeed * 2.1 + l.wobblePhase * 1.3) * 0.3;
      l.rotation = noise * (math.pi / 4) * (currentSpeed * 4.0).clamp(0.4, 1.2);
      if (l.localY > 1.2) _lanterns.removeAt(i);
    }

    for (int i = _blessings.length - 1; i >= 0; i--) {
      final b = _blessings[i];
      b.localY += currentSpeed * 0.8 * dt;
      b.opacity = (b.opacity - 0.15 * dt).clamp(0.0, 1.0);
      b.blur += 2.0 * dt;
      if (b.opacity <= 0) _blessings.removeAt(i);
    }
  }

  void _addBlessing(Offset position) {
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    final words = ["安", "顺", "福", "宁", "和"];
    final size = MediaQuery.of(context).size;
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
    
    DatabaseService.instance.recordEvent(RiverEvent(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: RiverEventType.activity,
      name: "祭江祈福",
      description: "在 ${challenge.currentSubSection?.name ?? '江面'} 举行祭江仪式",
      latitude: controller.lat,
      longitude: controller.lon,
      distanceAtKm: challenge.currentDistance,
    ));
  }

  void _addLantern() {
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    setState(() {
      _lanterns.add(Lantern(
        id: DateTime.now().millisecondsSinceEpoch.toDouble(),
        randomX: (math.Random().nextDouble() - 0.5) * 0.1,
        wobbleSpeed: 1.5 + math.Random().nextDouble() * 1.5,
        wobblePhase: math.Random().nextDouble() * math.pi * 2,
        scaleBase: 0.8 + math.Random().nextDouble() * 0.4,
      ));
    });
    
    DatabaseService.instance.recordEvent(RiverEvent(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: RiverEventType.activity,
      name: "放河灯",
      description: "在 ${challenge.currentSubSection?.name ?? '江面'} 放下一盏河灯",
      latitude: controller.lat,
      longitude: controller.lon,
      distanceAtKm: challenge.currentDistance,
    ));
  }

  Future<void> _loadShaders() async {
    _proceduralShader = (await ui.FragmentProgram.fromAsset('shaders/river.frag')).fragmentShader();
    _inkShader = (await ui.FragmentProgram.fromAsset('shaders/river_ink.frag')).fragmentShader();
    _auroraShader = (await ui.FragmentProgram.fromAsset('shaders/river_aurora.frag')).fragmentShader();
    if (mounted) setState(() {});
  }

  Future<void> _loadRealRiverPath(String path, String riverId) async {
    try {
      final data = json.decode(await rootBundle.loadString(path));
      List<Offset> pts = [];
      for (var s in data['sections_points']) {
        for (var p in s) pts.add(Offset(p[0].toDouble(), p[1].toDouble()));
      }
      List<double> dists = [0.0];
      double total = 0.0;
      for (int i = 1; i < pts.length; i++) {
        total += Geolocator.distanceBetween(pts[i-1].dy, pts[i-1].dx, pts[i].dy, pts[i].dx) / 1000.0;
        dists.add(total);
      }
      if (mounted) {
        setState(() { 
          _riverPoints = pts; 
          _cumulativeDistances = dists; 
          _loadedPointsRiverId = riverId;
        });
        _updatePathOffsets(context.read<ChallengeProvider>().currentDistance);
      }
    } catch (e) { debugPrint("Path Error: $e"); }
  }

  void _updatePathOffsets(double dist) {
    if (_riverPoints.isEmpty) return;
    List<double> offsets = [];
    int center = _findIdx(dist);
    for (int i = 0; i < 32; i++) {
      int idx = _findIdx(dist + (i / 31.0 - 0.5) * 20.0);
      offsets.add((_riverPoints[idx].dx - _riverPoints[center].dx) * 10.0);
    }
    setState(() => _currentPathOffsets = offsets);
  }

  int _findIdx(double d) {
    if (d <= 0) return 0;
    if (_cumulativeDistances.isEmpty) return 0;
    if (d >= _cumulativeDistances.last) return _cumulativeDistances.length - 1;
    int l = 0, h = _cumulativeDistances.length - 1;
    while (l <= h) {
      int m = (l + h) ~/ 2;
      if (_cumulativeDistances[m] < d) l = m + 1; else h = m - 1;
    }
    return l;
  }

  double _getRiverPathAt(double py, RiverSettings settings, SubSection? sub, double currentDistance) {
    final double scrollY = py + (currentDistance / 10.0) * 2.0;
    double path = (settings.pathMode == RiverPathMode.realPath && _riverPoints.isNotEmpty)
        ? _getInterpolatedOffset(py) * 0.5 : math.sin(scrollY * 1.5) * 0.25;
    return path + math.cos(scrollY * 3.5) * 0.05 * (settings.turbulence + ((sub?.difficulty ?? 3) * 0.1));
  }

  double _getInterpolatedOffset(double py) {
    double idx = (py * 0.5 + 0.5) * 31.0;
    int i = idx.floor().clamp(0, 31);
    int j = (i + 1).clamp(0, 31);
    return _currentPathOffsets[i] * (1 - (idx - i)) + _currentPathOffsets[j] * (idx - i);
  }

  void _showWeatherDetail(FlowController controller) {
    final weatherType = _mapWeatherCode(controller.wmoCode);
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: const Text("当前位置与天气", style: TextStyle(fontWeight: FontWeight.w300)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("位置: ${controller.cityName}", style: const TextStyle(fontSize: 18)),
        const Divider(),
        Text("当前温度: ${controller.temp} (${weatherType.label})"),
        Text("今日温差: ${controller.minTemp} ~ ${controller.maxTemp}"),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("确定"))],
    ));
  }

  WeatherType _mapWeatherCode(int code) {
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final controller = context.watch<FlowController>();
    final challenge = context.watch<ChallengeProvider>();
    
    if (challenge.isLoading || challenge.allSubSections.isEmpty || _proceduralShader == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    final sub = challenge.currentSubSection;

    return ListenableBuilder(
      listenable: RiverSettings.instance,
      builder: (context, _) {
        final settings = RiverSettings.instance;
        final shader = settings.style == RiverStyle.ink ? (_inkShader ?? _proceduralShader!)
                     : settings.style == RiverStyle.aurora ? (_auroraShader ?? _proceduralShader!)
                     : _proceduralShader!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            onDoubleTap: _addLantern,
            onLongPressStart: (d) => _addBlessing(d.localPosition),
            child: Listener(
              onPointerDown: (e) => setState(() => _pointers.add(e.pointer)),
              onPointerUp: (e) => setState(() => _pointers.remove(e.pointer)),
              onPointerMove: (e) {
                if (_pointers.length == 2) {
                  challenge.updateDistance(challenge.currentDistance - e.delta.dy * 0.5);
                  if (settings.pathMode == RiverPathMode.realPath) {
                    _updatePathOffsets(challenge.currentDistance);
                  }
                }
              },
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: RiverShaderPainter(
                  shader: shader,
                  useRealPath: settings.pathMode == RiverPathMode.realPath,
                  pathOffsets: _currentPathOffsets,
                  time: _stopwatch.elapsedMilliseconds / 1000.0,
                  turbulence: settings.turbulence + ((sub?.difficulty ?? 3) * 0.1),
                  width: settings.width + ((sub?.baseFlowSpeed ?? 0.5) * 0.02),
                  speed: settings.speed + ((sub?.baseFlowSpeed ?? 0.5) * 0.1),
                  themeColor: sub?.color ?? Colors.blue,
                  offset: challenge.currentDistance / 10.0,
                  pulse: _pulseController.value,
                  pulseX: _pulseCenter.dx,
                  pulseY: _pulseCenter.dy,
                ))),
                ..._blessings.map((b) => _buildBlessingWidget(b, settings, sub, challenge.currentDistance)),
                ..._lanterns.map((l) => _buildLanternWidget(l, settings, sub, challenge.currentDistance)),
                SafeArea(child: Column(children: [
                  const SizedBox(height: 25),
                  _buildHeader(sub, controller),
                  const Spacer(flex: 3),
                  _buildStepsAndProgress(controller, challenge),
                  const Spacer(flex: 4),
                ])),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBlessingWidget(Blessing b, RiverSettings settings, SubSection? sub, double currentDistance) {
    final x = (_getRiverPathAt(b.localY, settings, sub, currentDistance) + b.randomX) / (MediaQuery.of(context).size.aspectRatio);
    return Positioned(
      left: (x * 0.5 + 0.5) * MediaQuery.of(context).size.width - 25,
      top: (b.localY * 0.5 + 0.5) * MediaQuery.of(context).size.height - 25,
      child: Opacity(opacity: b.opacity, child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: b.blur, sigmaY: b.blur),
        child: Text(b.text, style: const TextStyle(fontSize: 52, color: Color(0xFFFFD700), fontWeight: FontWeight.w600, shadows: [
          Shadow(color: Colors.orangeAccent, blurRadius: 15),
          Shadow(color: Colors.black45, blurRadius: 5, offset: Offset(2, 2)),
        ])),
      )),
    );
  }

  Widget _buildLanternWidget(Lantern l, RiverSettings settings, SubSection? sub, double currentDistance) {
    final x = (_getRiverPathAt(l.localY, settings, sub, currentDistance) + l.randomX) / (MediaQuery.of(context).size.aspectRatio);
    final scale = l.scaleBase * (0.8 + (l.localY + 1.0) * 0.2);
    return Positioned(
      left: (x * 0.5 + 0.5) * MediaQuery.of(context).size.width - 25,
      top: (l.localY * 0.5 + 0.5) * MediaQuery.of(context).size.height - 25,
      child: Transform.rotate(angle: l.rotation, child: Opacity(
        opacity: (1.0 - (l.localY.abs() - 0.8).clamp(0.0, 0.2) / 0.2),
        child: Image.asset('assets/icons/light.png', width: 50 * scale, height: 50 * scale,
          color: settings.style == RiverStyle.aurora ? Colors.white.withOpacity(0.9) : null,
          colorBlendMode: settings.style == RiverStyle.aurora ? BlendMode.plus : null,
        ),
      )),
    );
  }

  Widget _buildHeader(SubSection? sub, FlowController controller) {
    final weatherType = _mapWeatherCode(controller.wmoCode);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 45), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        GestureDetector(
          onTap: () => RiverSelectorSheet.show(context),
          child: Row(
            children: [
              Text(sub?.name.split('·')[0] ?? '江面', style: const TextStyle(color: Color(0xFF222222), fontSize: 18, fontWeight: FontWeight.w400)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Color(0xFF888888)),
            ],
          ),
        ),
        GestureDetector(onTap: () => _showWeatherDetail(controller), child: Row(children: [
          Text(controller.temp, style: const TextStyle(color: Color(0xFF222222), fontSize: 18, fontWeight: FontWeight.w300)),
          const SizedBox(width: 8),
          Icon(weatherType.icon, size: 22, color: const Color(0xFF222222)),
        ])),
      ]),
      Text(sub?.name ?? '正在加载...', style: TextStyle(color: const Color(0xFF222222).withOpacity(0.5), fontSize: 13)),
    ]));
  }

  Widget _buildStepsAndProgress(FlowController controller, ChallengeProvider challenge) {
    String steps = controller.displaySteps.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return Column(children: [
      Text(steps, style: TextStyle(color: const Color(0xFF222222), fontSize: steps.length > 7 ? 82 : 105, fontWeight: FontWeight.w100, letterSpacing: -2)),
      Text("已行至 ${challenge.currentDistance.toStringAsFixed(1)} km / ${challenge.activeRiver?.totalLengthKm.round()} km", style: TextStyle(color: const Color(0xFF555555).withOpacity(0.7), fontSize: 16, letterSpacing: 1.2)),
    ]);
  }
}

class RiverShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final bool useRealPath;
  final List<double> pathOffsets;
  final double time, turbulence, width, speed, offset, pulse, pulseX, pulseY;
  final Color themeColor;

  RiverShaderPainter({required this.shader, required this.useRealPath, required this.pathOffsets, required this.time,
    required this.turbulence, required this.width, required this.speed, required this.themeColor, required this.offset,
    required this.pulse, required this.pulseX, required this.pulseY});

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
    for (int i = 0; i < 32; i++) shader.setFloat(11 + i, pathOffsets[i]);
    shader.setFloat(43, pulse);
    shader.setFloat(44, pulseX);
    shader.setFloat(45, pulseY);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
