import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/river_settings.dart';
import '../models/daily_stats.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/flow_models.dart';
import '../controllers/flow_controller.dart';
import '../providers/challenge_provider.dart';
import '../models/river_section.dart';
import '../services/river_drift_service.dart';
import 'lantern_ritual_screen.dart';
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
  /// 已行至在屏幕上方 1/3 处时的视口偏移：视口中心 = 已行至 + 此值（km）
  static const double _kOneThirdFromTopOffsetKm = 0.5;

  // 视觉距离（用于动画过渡）
  double _visualDistance = 0.0;
  late AnimationController _distanceController;

  // 渲染专用
  ui.FragmentShader? _proceduralShader;
  ui.FragmentShader? _inkShader;
  ui.FragmentShader? _auroraShader;

  List<Offset> _riverPoints = [];
  List<double> _cumulativeDistances = [];
  List<double> _currentPathOffsets = List.filled(32, 0.0);
  String? _loadedPointsRiverId;

  final List<Blessing> _blessings = [];
  double _lastFrameTime = 0;

  /// 河灯/漂流瓶：从 DB 加载，按虚拟源头时间戳计算当前位置
  RiverDriftTimeline? _driftTimeline;
  List<RiverEvent> _driftEvents = [];
  bool _driftEventsLoaded = false;
  String? _driftTimelineRiverId;
  double? _lastDriftCrossScreenSeconds;
  /// 刚放下的河灯 timestamp，用于主屏渐入动画，动画结束后置 null
  int? _lastAddedLanternTimestamp;
  late AnimationController _driftFadeInController;

  // 里程碑相关
  String? _lastTriggeredSubSectionName;
  String? _milestoneMedalPath;
  late AnimationController _milestoneController;

  // 当前里程对应 POI（按行进距离查最近点，约 0.5 km 刷新一次）
  RiverPoi? _currentPoi;
  double? _lastPoiRequestKm;

  late AnimationController _timeController;
  late AnimationController _pulseController;
  Offset _pulseCenter = Offset.zero;

  late Stopwatch _stopwatch;
  final Set<int> _pointers = {};
  VoidCallback? _flowControllerListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 传感器触发 → 同步写 DB → FlowController 从 DB 读出步数+里程并 notify。此处同步视觉距离时：
    // 1) 若用户已双指滑走，不因步数更新而拉回，等回到当前位置后再随步数更新；
    // 2) 若当前展示的就是真实里程（例如双击回到当前位置后），则随步数/里程更新。
    _flowControllerListener = () {
      if (!mounted) return;
      final controller = context.read<FlowController>();
      final challenge = context.read<ChallengeProvider>();
      final realKm = controller.currentDistance;
      final displayIsReal = (challenge.currentDistance - realKm).abs() < 0.001;
      final targetCenter = realKm + _kOneThirdFromTopOffsetKm;
      final viewingNearReal = (_visualDistance - targetCenter).abs() < 0.8;
      if (_distanceController.isAnimating) return;
      if (displayIsReal || viewingNearReal) {
        if ((_visualDistance - targetCenter).abs() > 0.001) {
          setState(() => _visualDistance = challenge.currentDistance + _kOneThirdFromTopOffsetKm);
        }
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FlowController>().addListener(_flowControllerListener!);
    });

    _distanceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _milestoneController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _timeController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
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

    _driftFadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _driftFadeInController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _lastAddedLanternTimestamp = null);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FlowController>().init();
      context.read<FlowController>().startStepListening();
      _refreshWeather();
      // 进入涉川首页即触发一次 POI 查询，不依赖定时器
      _updateFrame();
    });

    _loadShaders();
  }

  void _updateFrame() {
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    final realKm = controller.currentDistance;
    final targetCenter = realKm + _kOneThirdFromTopOffsetKm;
    final viewingNearReal = (_visualDistance - targetCenter).abs() < 0.8;

    // 仅在「未双指滑走」时同步视觉距离；滑走后等用户回到当前位置再随步数更新；已行至在屏上 1/3 处
    if (!_distanceController.isAnimating && viewingNearReal) {
      if ((_visualDistance - targetCenter).abs() > 5.0) {
        _animateTo(challenge.currentDistance + _kOneThirdFromTopOffsetKm);
      } else {
        _visualDistance = challenge.currentDistance + _kOneThirdFromTopOffsetKm;
      }
    }

    // 里程碑边界检测
    final currentSub = challenge.currentSubSection;
    if (currentSub != null && _lastTriggeredSubSectionName != currentSub.name) {
      if (_lastTriggeredSubSectionName != null) {
        _triggerMilestone(currentSub);
      }
      _lastTriggeredSubSectionName = currentSub.name;
    }

    if (challenge.activeRiver != null &&
        _loadedPointsRiverId != challenge.activeRiver!.id) {
      _loadRealRiverPath(
          challenge.activeRiver!.pointsJsonPath, challenge.activeRiver!.id);
      _lastPoiRequestKm = null;
      _currentPoi = null;
    }

    // 切换河流时重建漂流时间轴并重新加载漂流事件
    final currentRiverId = challenge.activeRiver?.id;
    if (currentRiverId != null && _driftTimeline != null) {
      // 若河流 ID 与构建时间轴时不一致（如切换河流），重置以便用新河流的 subsection 重建
      if (_driftTimelineRiverId != currentRiverId) {
        _driftTimeline = null;
        _driftEventsLoaded = false;
        _driftTimelineRiverId = currentRiverId;
      }
    } else if (currentRiverId != null) {
      _driftTimelineRiverId = currentRiverId;
    }

    // 按当前行进距离查最近 POI：仅在挑战加载完成、河流有效且 numericId>0 时查询，避免时序导致匹配不到
    // 约 0.5 km 更新一次；加载完成后 _lastPoiRequestKm 为 null 会触发首次查询
    final river = challenge.activeRiver;
    final km = challenge.currentDistance;
    final canQueryPoi = !challenge.isLoading &&
        river != null &&
        river.numericId > 0 &&
        (_lastPoiRequestKm == null || (km - _lastPoiRequestKm!).abs() >= 0.5);
    if (canQueryPoi) {
      _lastPoiRequestKm = km;
      DatabaseService.instance.getNearestPoi(river.numericId, km).then((p) {
        if (!mounted) return;
        // 仅在有结果时更新，避免查询抛错被 catch 成 null 后把之前有效的 POI 清掉
        if (p != null) setState(() => _currentPoi = p);
      });
    }

    // 过屏时间设置变更时重建时间轴，使新倍数生效
    final driftSec = RiverSettings.instance.driftCrossScreenSeconds;
    if (_lastDriftCrossScreenSeconds != null &&
        (driftSec - _lastDriftCrossScreenSeconds!).abs() > 0.5) {
      _driftTimeline = null;
    }
    _lastDriftCrossScreenSeconds = driftSec;

    // 漂流时间轴：挑战加载完成后构建一次；漂流事件加载一次
    if (_driftTimeline == null &&
        challenge.allSubSections.isNotEmpty) {
      _driftTimeline = RiverDriftTimeline.fromSubSections(
        challenge.allSubSections,
        visibleRangeKm: 3.0,
        targetCrossScreenSeconds: driftSec,
      );
      _driftTimelineRiverId = challenge.activeRiver?.id;
      if (!_driftEventsLoaded) _loadDriftEvents();
    }
    _updateBlessingsOnly(challenge.currentSubSection);
  }

  Future<void> _loadDriftEvents() async {
    final list = await DatabaseService.instance.getDriftEvents();
    if (!mounted) return;
    setState(() {
      _driftEvents = list;
      _driftEventsLoaded = true;
    });
  }

  /// 轻震：祭江、放河灯等事件用，比跨河段震感更轻
  void _triggerLightHaptic() {
    if (Platform.isAndroid) {
      Vibration.hasVibrator().then((has) {
        if (has == true) Vibration.vibrate(duration: 20);
      });
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _triggerMilestone(SubSection sub) {
    // 进入新河段即震动。iOS 保持系统 HapticFeedback；Android 上 Flutter 的 HapticFeedback 常无感，改用原生 Vibrator 保证有震感。
    if (Platform.isAndroid) {
      // 使用原生 Vibrator，避免 Flutter HapticFeedback 在部分 Android 设备上无感
      Vibration.hasVibrator().then((has) {
        if (has == true) Vibration.vibrate(duration: 40);
      });
    } else {
      HapticFeedback.heavyImpact();
    }

    if (sub.medalIcon == null) return;

    setState(() {
      _milestoneMedalPath = sub.medalIcon;
    });
    _pulseController.reset();
    _pulseController.forward();
    _milestoneController.reset();
    _milestoneController.forward();
  }

  void _animateTo(double target) {
    final start = _visualDistance;
    _distanceController.reset();
    final Animation<double> animation = Tween<double>(begin: start, end: target)
        .animate(CurvedAnimation(
            parent: _distanceController, curve: Curves.easeInOutCubic));

    animation.addListener(() {
      if (mounted) {
        setState(() {
          _visualDistance = animation.value;
          if (RiverSettings.instance.pathMode == RiverPathMode.realPath) {
            _updatePathOffsets(_visualDistance);
          }
        });
      }
    });
    _distanceController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_flowControllerListener != null) {
      try {
        context.read<FlowController>().removeListener(_flowControllerListener!);
      } catch (_) {}
    }
    _timeController.dispose();
    _distanceController.dispose();
    _milestoneController.dispose();
    _pulseController.dispose();
    _driftFadeInController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = context.read<FlowController>();
    if (state == AppLifecycleState.paused) {
      controller.saveWeatherToDatabase();
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
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      Position? pos;

      if (serviceEnabled) {
        try {
          // Android 上使用 medium 可更快拿到结果，减少超时
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 15),
            ),
          );
        } catch (e) {
          debugPrint("getCurrentPosition failed: $e");
          // Android 授权后有时需稍等再取位置，重试一次
          if (Platform.isAndroid) {
            await Future.delayed(const Duration(milliseconds: 800));
            try {
              pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.low,
                  timeLimit: Duration(seconds: 10),
                ),
              );
            } catch (e2) {
              debugPrint("getCurrentPosition retry failed: $e2");
            }
          }
        }
      }

      // 定位未开或 getCurrentPosition 超时/失败时，用上次缓存位置拉天气（Android 常见）
      pos ??= await Geolocator.getLastKnownPosition();

      double? lat;
      double? lon;
      if (pos != null) {
        lat = pos.latitude;
        lon = pos.longitude;
      } else {
        // 仍无位置时用上次天气缓存的坐标拉一次（Android 上常出现首次/室内无定位）
        final prefs = await SharedPreferences.getInstance();
        final String? cached = prefs.getString('cached_weather_v2');
        if (cached != null) {
          try {
            final data = json.decode(cached) as Map<String, dynamic>;
            final latNum = data['lat'];
            final lonNum = data['lon'];
            if (latNum != null && lonNum != null) {
              lat = (latNum as num).toDouble();
              lon = (lonNum as num).toDouble();
            }
          } catch (_) {}
        }
      }

      if (lat != null && lon != null && mounted) {
        context.read<FlowController>().fetchWeather(lat, lon);
      }
    } catch (e) {
      debugPrint("_refreshWeather error: $e");
    }
  }

  /// 仅更新祭江祈福的动画；河灯/漂流瓶位置由虚拟源头时间戳每帧计算
  void _updateBlessingsOnly(SubSection? sub) {
    final double currentTime = _stopwatch.elapsedMilliseconds / 1000.0;
    if (_lastFrameTime == 0) {
      _lastFrameTime = currentTime;
      return;
    }
    final double dt = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    if (sub == null) return;

    final double currentSpeed =
        (RiverSettings.instance.speed + (sub.baseFlowSpeed * 0.1)) * 0.5;

    for (int i = _blessings.length - 1; i >= 0; i--) {
      final b = _blessings[i];
      b.localY += currentSpeed * 0.8 * dt;
      b.opacity = (b.opacity - 0.15 * dt).clamp(0.0, 1.0);
      b.blur += 2.0 * dt;
      if (b.opacity <= 0) _blessings.removeAt(i);
    }
  }

  void _addBlessing(Offset position, {String? text}) {
    _triggerLightHaptic();
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    final words = ["安", "顺", "福", "宁", "和"];
    final size = MediaQuery.of(context).size;
    final displayText = (text != null && text.trim().isNotEmpty)
        ? text.trim()
        : words[math.Random().nextInt(words.length)];
    final sectionName = challenge.currentSubSection?.name ?? '江面';
    setState(() {
      _pulseCenter =
          Offset(position.dx / size.width, position.dy / size.height);
      _blessings.add(Blessing(
        text: displayText,
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
      description: "在 $sectionName 举行祭江仪式${displayText.isNotEmpty ? '：$displayText' : ''}",
      latitude: controller.lat,
      longitude: controller.lon,
      distanceAtKm: challenge.realDistance,
    ));
  }

  void _openLanternRitual() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, _, __) => ChangeNotifierProvider<FlowController>.value(
          value: context.read<FlowController>(),
          child: ChangeNotifierProvider<ChallengeProvider>.value(
            value: context.read<ChallengeProvider>(),
            child: LanternRitualScreen(
              mode: RitualMode.lantern,
              onComplete: (wish) => _addLantern(wish: wish),
            ),
          ),
        ),
      ),
    );
  }

  void _openBottleRitual() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, _, __) => ChangeNotifierProvider<FlowController>.value(
          value: context.read<FlowController>(),
          child: ChangeNotifierProvider<ChallengeProvider>.value(
            value: context.read<ChallengeProvider>(),
            child: LanternRitualScreen(
              mode: RitualMode.bottle,
              onComplete: (message) => _addBottle(message: message),
            ),
          ),
        ),
      ),
    );
  }

  void _addLantern({String? wish}) {
    _triggerLightHaptic();
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    // 释放位置为当前屏幕 1/3 处对应的公里数（滑动时也能看到河灯）
    final totalKm = challenge.activeRiver?.totalLengthKm ?? 0.0;
    final dropKm = (_visualDistance - _kOneThirdFromTopOffsetKm).clamp(0.0, totalKm);
    final extraData = wish != null && wish.isNotEmpty
        ? jsonEncode({'wish': wish})
        : '{}';
    final event = RiverEvent(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: RiverEventType.activity,
      name: "放河灯",
      description: "在 ${challenge.currentSubSection?.name ?? '江面'} 放下一盏河灯",
      latitude: controller.lat,
      longitude: controller.lon,
      distanceAtKm: dropKm,
      extraData: extraData,
    );
    DatabaseService.instance.recordEvent(event);
    setState(() => _driftEvents.add(event));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastAddedLanternTimestamp = event.timestamp;
      _driftFadeInController.forward(from: 0);
    });
  }

  void _addBottle({String? message}) {
    _triggerLightHaptic();
    final controller = context.read<FlowController>();
    final challenge = context.read<ChallengeProvider>();
    final sectionName = challenge.currentSubSection?.name ?? '江面';
    // 释放位置为当前屏幕 1/3 处对应的公里数（滑动时也能看到河灯）
    final totalKm = challenge.activeRiver?.totalLengthKm ?? 0.0;
    final dropKm = (_visualDistance - _kOneThirdFromTopOffsetKm).clamp(0.0, totalKm);
    final desc = message != null && message.trim().isNotEmpty
        ? "在 $sectionName 放下漂流瓶\n\n${message.trim()}"
        : "在 $sectionName 放下漂流瓶";
    final event = RiverEvent(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: RiverEventType.activity,
      name: "水畔寄书",
      description: desc,
      latitude: controller.lat,
      longitude: controller.lon,
      distanceAtKm: dropKm,
    );
    DatabaseService.instance.recordEvent(event);
    setState(() => _driftEvents.add(event));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastAddedLanternTimestamp = event.timestamp;
      _driftFadeInController.forward(from: 0);
    });
  }

  Future<void> _showBlessingInputDialog(Size size) async {
    final text = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => _RitualTextInputDialog(
        title: '临川祈愿',
        hint: '八字以内，写下祈福',
        maxLength: 8,
        maxLines: 1,
        confirmLabel: '祈愿',
      ),
    );
    if (!mounted) return;
    if (text != null) _addBlessing(Offset(size.width / 2, size.height / 2), text: text);
  }

  void _showRitualSheet() {
    final size = MediaQuery.of(context).size;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFF222222).withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '开始仪式',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 3,
                    color: const Color(0xFF222222).withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 24),
                _ritualTile(
                  ctx,
                  icon: Icons.nightlight_round_outlined,
                  title: '星河流灯',
                  subtitle: '净心 · 寄愿 · 放灯入江',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openLanternRitual();
                  },
                ),
                const SizedBox(height: 12),
                _ritualTile(
                  ctx,
                  icon: Icons.send_outlined,
                  title: '水畔寄书',
                  subtitle: '净心 · 寄语 · 放瓶入江',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBottleRitual();
                  },
                ),
                const SizedBox(height: 12),
                _ritualTile(
                  ctx,
                  icon: Icons.auto_awesome,
                  title: '临川祈愿',
                  subtitle: '八字以内，在江面留下祈福',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showBlessingInputDialog(size);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ritualTile(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF222222).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: const Color(0xFF222222).withOpacity(0.65)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF222222),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF222222).withOpacity(0.45),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: const Color(0xFF222222).withOpacity(0.25)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadShaders() async {
    _proceduralShader =
        (await ui.FragmentProgram.fromAsset('shaders/river.frag'))
            .fragmentShader();
    _inkShader = (await ui.FragmentProgram.fromAsset('shaders/river_ink.frag'))
        .fragmentShader();
    _auroraShader =
        (await ui.FragmentProgram.fromAsset('shaders/river_aurora.frag'))
            .fragmentShader();
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
        total += Geolocator.distanceBetween(
                pts[i - 1].dy, pts[i - 1].dx, pts[i].dy, pts[i].dx) /
            1000.0;
        dists.add(total);
      }
      if (mounted) {
        setState(() {
          _riverPoints = pts;
          _cumulativeDistances = dists;
          _loadedPointsRiverId = riverId;
        });
        _updatePathOffsets(_visualDistance);
      }
    } catch (e) {
      debugPrint("Path Error: $e");
    }
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
      if (_cumulativeDistances[m] < d)
        l = m + 1;
      else
        h = m - 1;
    }
    return l;
  }

  double _getRiverPathAt(double py, RiverSettings settings, SubSection? sub,
      double currentDistance) {
    final double scrollY = py + (currentDistance / 10.0) * 2.0;
    double path =
        (settings.pathMode == RiverPathMode.realPath && _riverPoints.isNotEmpty)
            ? _getInterpolatedOffset(py) * 0.5
            : math.sin(scrollY * 1.5) * 0.25;
    return path +
        math.cos(scrollY * 3.5) *
            0.05 *
            (settings.turbulence + ((sub?.difficulty ?? 3) * 0.1));
  }

  double _getInterpolatedOffset(double py) {
    double idx = (py * 0.5 + 0.5) * 31.0;
    int i = idx.floor().clamp(0, 31);
    int j = (i + 1).clamp(0, 31);
    return _currentPathOffsets[i] * (1 - (idx - i)) +
        _currentPathOffsets[j] * (idx - i);
  }

  void _showWeatherDetail(FlowController controller) {
    final weatherType = _mapWeatherCode(controller.wmoCode);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              backgroundColor: Colors.white.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25)),
              title: const Text("环境详情",
                  style: TextStyle(fontWeight: FontWeight.w300)),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text("${controller.cityName}",
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w400))),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text(
                        "经纬度: ${controller.lat.toStringAsFixed(4)}, ${controller.lon.toStringAsFixed(4)}",
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    const Divider(height: 30),
                    _buildWeatherRow(weatherType.icon, "当前天气",
                        "${controller.temp} (${weatherType.label})"),
                    _buildWeatherRow(Icons.thermostat_outlined, "体感温度",
                        controller.apparentTemp),
                    _buildWeatherRow(Icons.wb_sunny_outlined, "今日温差",
                        "${controller.minTemp} ~ ${controller.maxTemp}"),
                    _buildWeatherRow(Icons.air_rounded, "实时风速",
                        "${controller.windSpeed} km/h"),
                    _buildWeatherRow(
                        Icons.water_drop_outlined, "相对湿度", controller.humidity),
                    _buildWeatherRow(Icons.cloud_circle_outlined, "空气质量",
                        "AQI ${controller.aqi} (PM2.5: ${controller.pm2_5})"),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c), child: const Text("确定"))
              ],
            ));
  }

  Widget _buildWeatherRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey.shade700),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
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

    if (challenge.isLoading ||
        challenge.allSubSections.isEmpty ||
        _proceduralShader == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 初始化视觉距离（已行至在屏上 1/3 处）
    if (_visualDistance == 0 && challenge.currentDistance != 0) {
      _visualDistance = challenge.currentDistance + _kOneThirdFromTopOffsetKm;
    }

    final sub = challenge.currentSubSection;

    return ListenableBuilder(
      listenable: RiverSettings.instance,
      builder: (context, _) {
        final settings = RiverSettings.instance;
        final shader = settings.style == RiverStyle.ink
            ? (_inkShader ?? _proceduralShader!)
            : settings.style == RiverStyle.aurora
                ? (_auroraShader ?? _proceduralShader!)
                : _proceduralShader!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            onDoubleTap: _openLanternRitual,
            onLongPressStart: (d) => _addBlessing(d.localPosition),
            child: Listener(
              onPointerDown: (e) => setState(() => _pointers.add(e.pointer)),
              onPointerUp: (e) => setState(() => _pointers.remove(e.pointer)),
              onPointerMove: (e) {
                if (_pointers.length == 2) {
                  if (_distanceController.isAnimating)
                    _distanceController.stop();
                  final prevSubName = challenge.currentSubSection?.name;
                  challenge.updateVirtualDistance(
                      challenge.currentDistance - e.delta.dy * 0.5);
                  _visualDistance = challenge.currentDistance;
                  if (settings.pathMode == RiverPathMode.realPath) {
                    _updatePathOffsets(_visualDistance);
                  }
                  // 双指滑动后立即检测是否跨河段，立即震动（不依赖定时器）
                  final nowSub = challenge.currentSubSection;
                  if (nowSub != null &&
                      nowSub.name != prevSubName &&
                      prevSubName != null) {
                    _lastTriggeredSubSectionName = nowSub.name;
                    _triggerMilestone(nowSub);
                  }
                }
              },
              child: Stack(children: [
                Positioned.fill(
                    child: CustomPaint(
                        painter: RiverShaderPainter(
                  shader: shader,
                  useRealPath: settings.pathMode == RiverPathMode.realPath,
                  pathOffsets: _currentPathOffsets,
                  time: _stopwatch.elapsedMilliseconds / 1000.0,
                  turbulence:
                      settings.turbulence + ((sub?.difficulty ?? 3) * 0.1),
                  width: settings.width + ((sub?.baseFlowSpeed ?? 0.5) * 0.02),
                  speed: settings.speed + ((sub?.baseFlowSpeed ?? 0.5) * 0.1),
                  themeColor: sub?.color ?? Colors.blue,
                  offset: _visualDistance / 10.0,
                  pulse: _pulseController.value,
                  pulseX: _pulseCenter.dx,
                  pulseY: _pulseCenter.dy,
                ))),
                ..._blessings.map((b) =>
                    _buildBlessingWidget(b, settings, sub, _visualDistance)),
                ..._buildVisibleDriftWidgets(settings, sub),

                // 里程碑勋章浮现层
                if (_milestoneMedalPath != null) _buildMilestoneOverlay(),

                SafeArea(
                    child: Column(children: [
                  const SizedBox(height: 25),
                  _buildHeader(sub, controller),
                  const SizedBox(height: 20),
                  _buildPoiCard(sub, controller),
                  const Spacer(flex: 3),
                  _buildStepsAndProgress(
                      controller, challenge, challenge.currentDistance),
                  const Spacer(flex: 4),
                ])),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMilestoneOverlay() {
    return AnimatedBuilder(
      animation: _milestoneController,
      builder: (context, child) {
        final double val = _milestoneController.value;
        if (val <= 0 || val >= 1.0) return const SizedBox();

        double opacity = 1.0;
        double scale = 1.0;

        if (val < 0.2) {
          opacity = val / 0.2;
          scale = 0.5 + (val / 0.2) * 0.5;
        } else if (val > 0.8) {
          opacity = (1.0 - val) / 0.2;
          scale = 1.0 + ((val - 0.8) / 0.2) * 0.2;
        }

        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.3),
                          blurRadius: 40,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                    child: Image.asset(
                      'assets/$_milestoneMedalPath',
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.military_tech,
                          size: 100,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "解锁新境界",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 根据虚拟源头时间戳计算当前可见的河灯/漂流瓶并返回对应 Widget 列表
  List<Widget> _buildVisibleDriftWidgets(
      RiverSettings settings, SubSection? sub) {
    final timeline = _driftTimeline;
    if (timeline == null || _driftEvents.isEmpty) return [];

    final tNowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final (dMin, dMax) = timeline.visibleRange(_visualDistance);
    final currentTime = _stopwatch.elapsedMilliseconds / 1000.0;
    final List<Widget> out = [];

    for (final event in _driftEvents) {
      final dropSec = event.timestamp / 1000.0;
      final virtualSourceSec =
          timeline.calculateVirtualSourceTimestamp(event.distanceAtKm, dropSec);
      final currentDist =
          timeline.calculateCurrentDistance(virtualSourceSec, tNowSec);
      if (currentDist < 0 || currentDist > timeline.totalLengthKm) continue;
      if (currentDist < dMin || currentDist > dMax) continue;

      final localY = timeline.kmToLocalY(currentDist, _visualDistance);
      final seed = event.id ?? event.timestamp;
      final randomX = ((seed % 1000) / 1000.0 - 0.5) * 0.1;
      final scaleBase = 0.8 + ((seed % 500) / 500.0) * 0.4;
      final wobblePhase = (seed % 1000) / 1000.0 * math.pi * 2;
      final rotation = (math.sin(currentTime * 1.5 + wobblePhase) * 0.7 +
              math.sin(currentTime * 2.1 + wobblePhase * 1.3) * 0.3) *
          (math.pi / 4);

      final isLantern = event.name == '放河灯';
      out.add(_buildDriftItemWidget(
        isLantern: isLantern,
        eventTimestamp: event.timestamp,
        localY: localY,
        randomX: randomX,
        scaleBase: scaleBase,
        rotation: rotation,
        settings: settings,
        sub: sub,
        currentDistance: _visualDistance,
      ));
    }
    return out;
  }

  Widget _buildDriftItemWidget({
    required bool isLantern,
    required int eventTimestamp,
    required double localY,
    required double randomX,
    required double scaleBase,
    required double rotation,
    required RiverSettings settings,
    required SubSection? sub,
    required double currentDistance,
  }) {
    final x = (_getRiverPathAt(localY, settings, sub, currentDistance) +
            randomX) /
        (MediaQuery.of(context).size.aspectRatio);
    final scale = scaleBase * (0.8 + (localY + 1.0) * 0.2);
    final asset = isLantern ? 'assets/icons/light.png' : 'assets/icons/bottle.png';
    final content = Transform.rotate(
      angle: rotation,
      child: Opacity(
        opacity: (1.0 - (localY.abs() - 0.8).clamp(0.0, 0.2) / 0.2),
        child: Image.asset(
          asset,
          width: 50 * scale,
          height: 50 * scale,
          color: settings.style == RiverStyle.aurora
              ? Colors.white.withOpacity(0.9)
              : null,
          colorBlendMode:
              settings.style == RiverStyle.aurora ? BlendMode.plus : null,
        ),
      ),
    );
    final useFadeIn = isLantern &&
        _lastAddedLanternTimestamp != null &&
        eventTimestamp == _lastAddedLanternTimestamp;
    return Positioned(
      left: (x * 0.5 + 0.5) * MediaQuery.of(context).size.width - 25,
      top: (localY * 0.5 + 0.5) * MediaQuery.of(context).size.height - 25,
      child: useFadeIn
          ? FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(_driftFadeInController),
              child: content,
            )
          : content,
    );
  }

  Widget _buildBlessingWidget(Blessing b, RiverSettings settings,
      SubSection? sub, double currentDistance) {
    final x = (_getRiverPathAt(b.localY, settings, sub, currentDistance) +
            b.randomX) /
        (MediaQuery.of(context).size.aspectRatio);
    const maxW = 220.0;
    return Positioned(
      left: (x * 0.5 + 0.5) * MediaQuery.of(context).size.width - maxW / 2,
      top: (b.localY * 0.5 + 0.5) * MediaQuery.of(context).size.height - 30,
      child: Opacity(
          opacity: b.opacity,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: b.blur, sigmaY: b.blur),
            child: SizedBox(
              width: maxW,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(b.text,
                    style: const TextStyle(
                        fontSize: 52,
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Colors.orangeAccent, blurRadius: 15),
                          Shadow(
                              color: Colors.black45,
                              blurRadius: 5,
                              offset: Offset(2, 2)),
                        ])),
              ),
            ),
          )),
    );
  }

  /// 多个 POI 名称用顿号拼接，图标与文字同色且同一行
  List<Widget> _buildPoiNamesRow(List<PoiItem> poisList) {
    final names = poisList
        .map((p) => p.name?.trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    if (names.isEmpty) return [];
    final label = names.join('、');
    const textColor = Color(0xFF555555);
    const textOpacity = 0.9;
    final style = TextStyle(
      color: textColor.withOpacity(textOpacity),
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.3,
      height: 1.35,
    );
    return [
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.explore_rounded,
                size: 14, color: textColor.withOpacity(textOpacity)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ];
  }

  Widget _buildPoiCard(SubSection? sub, FlowController controller) {
    final poi = _currentPoi;
    final themeColor = sub?.color ?? const Color(0xFF2196F3);
    final isLight = themeColor.computeLuminance() > 0.4;
    // 地址主文案：有 POI 时用 shortLabel（省市区 + 最近 POI 名，如「青海省 海西 格尔木市 唐古拉山镇 · 沱沱河」）；无 POI 用天气城市名兜底
    final addressLine = poi != null
        ? poi.shortLabel
        : (controller.cityName.isNotEmpty && controller.cityName != "待定位"
            ? controller.cityName
            : "江心云水间");
    final hasAddress = addressLine.trim().isNotEmpty && addressLine != "江心云水间";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isLight ? 0.78 : 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: themeColor.withOpacity(0.18), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 8)),
            BoxShadow(
                color: themeColor.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.place_rounded,
                  size: 22, color: themeColor.withOpacity(0.85)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "此刻行至",
                    style: TextStyle(
                      color: const Color(0xFF222222).withOpacity(0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressLine,
                    style: TextStyle(
                      color: Color(0xFF222222)
                          .withOpacity(hasAddress ? 0.95 : 0.35),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                      height: 1.35,
                      fontStyle:
                          hasAddress ? FontStyle.normal : FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (poi != null) ...[
                    ..._buildPoiNamesRow(poi.poisList),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SubSection? sub, FlowController controller) {
    final weatherType = _mapWeatherCode(controller.wmoCode);
    final medalIcon = sub?.medalIcon;

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 45),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              onTap: () => RiverSelectorSheet.show(context),
              child: Row(
                children: [
                  Text(sub?.name.split('·')[0] ?? '江面',
                      style: const TextStyle(
                          color: Color(0xFF222222),
                          fontSize: 18,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: Color(0xFF888888)),
                ],
              ),
            ),
            Row(children: [
              GestureDetector(
                onTap: _showRitualSheet,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    size: 22,
                    color: const Color(0xFF222222).withOpacity(0.6),
                  ),
                ),
              ),
              if (medalIcon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Image.asset(
                    'assets/$medalIcon',
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              GestureDetector(
                  onTap: () => _showWeatherDetail(controller),
                  child: Row(children: [
                    Text(controller.temp,
                        style: const TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 18,
                            fontWeight: FontWeight.w300)),
                    const SizedBox(width: 8),
                    Icon(weatherType.icon,
                        size: 22, color: const Color(0xFF222222)),
                  ])),
            ]),
          ]),
          Text(sub?.name ?? '正在加载...',
              style: TextStyle(
                  color: const Color(0xFF222222).withOpacity(0.5),
                  fontSize: 13)),
        ]));
  }

  /// 步数与进度区：显示实际累计里程（非视口偏移），起步与到江尾时如实显示 0 与总长
  Widget _buildStepsAndProgress(FlowController controller,
      ChallengeProvider challenge, double accumulatedKm) {
    String steps = controller.displaySteps.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final sub = challenge.currentSubSection;
    final all = challenge.allSubSections;
    double segmentStartKm = 0;
    double segmentLengthKm = 0;
    if (sub != null && all.isNotEmpty) {
      final idx = all.indexOf(sub);
      segmentStartKm = idx > 0 ? all[idx - 1].accumulatedLength : 0;
      segmentLengthKm = sub.accumulatedLength - segmentStartKm;
    }
    final segmentTraveledKm =
        (accumulatedKm - segmentStartKm).clamp(0.0, segmentLengthKm);
    final segmentLine = segmentLengthKm > 0
        ? "本段已行 ${segmentTraveledKm.toStringAsFixed(1)} km / 本段 ${segmentLengthKm.toStringAsFixed(0)} km"
        : null;
    final stepsSource = controller.stepsSource;
    final isHealthConnect = stepsSource == 'health_connect';
    final isSensor = stepsSource == 'sensor';
    return Column(children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            child: Tooltip(
              message: isHealthConnect
                  ? '步数来自 Health Connect'
                  : isSensor
                      ? '步数来自计步传感器'
                      : '步数来源未知',
              child: Icon(
                isHealthConnect
                    ? Icons.health_and_safety_outlined
                    : isSensor
                        ? Icons.sensors_outlined
                        : Icons.help_outline_rounded,
                size: 20,
                color: const Color(0xFF888888),
              ),
            ),
          ),
          Text(steps,
              style: TextStyle(
                  color: const Color(0xFF222222),
                  fontSize: steps.length > 7 ? 82 : 105,
                  fontWeight: FontWeight.w100,
                  letterSpacing: -2)),
        ],
      ),
      Text(
          "已行至 ${accumulatedKm.toStringAsFixed(1)} km / ${challenge.activeRiver?.totalLengthKm.round()} km",
          style: TextStyle(
              color: const Color(0xFF555555).withOpacity(0.7),
              fontSize: 16,
              letterSpacing: 1.2)),
      if (segmentLine != null) ...[
        const SizedBox(height: 10),
        Text(segmentLine,
            style: TextStyle(
                color: const Color(0xFF555555).withOpacity(0.6),
                fontSize: 14,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.8)),
      ],
    ]);
  }
}

class _RitualTextInputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final int maxLength;
  final int maxLines;
  final String confirmLabel;

  const _RitualTextInputDialog({
    required this.title,
    required this.hint,
    required this.maxLength,
    required this.maxLines,
    required this.confirmLabel,
  });

  @override
  State<_RitualTextInputDialog> createState() => _RitualTextInputDialogState();
}

class _RitualTextInputDialogState extends State<_RitualTextInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white.withOpacity(0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          letterSpacing: 1.5,
          color: Color(0xFF222222),
        ),
      ),
      content: TextField(
        controller: _controller,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: const Color(0xFF222222).withOpacity(0.35),
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
          counterStyle: TextStyle(
            color: const Color(0xFF222222).withOpacity(0.4),
            fontSize: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFF222222).withOpacity(0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFF222222).withOpacity(0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFF222222).withOpacity(0.35), width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        style: const TextStyle(fontSize: 15, color: Color(0xFF222222), height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(color: const Color(0xFF222222).withOpacity(0.5), fontSize: 15),
          ),
        ),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.pop(context, text.isEmpty ? null : text);
          },
          child: Text(
            widget.confirmLabel,
            style: const TextStyle(
              color: Color(0xFF222222),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class RiverShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final bool useRealPath;
  final List<double> pathOffsets;
  final double time, turbulence, width, speed, offset, pulse, pulseX, pulseY;
  final Color themeColor;

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
    for (int i = 0; i < 32; i++) shader.setFloat(11 + i, pathOffsets[i]);
    shader.setFloat(43, pulse);
    shader.setFloat(44, pulseX);
    shader.setFloat(45, pulseY);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
