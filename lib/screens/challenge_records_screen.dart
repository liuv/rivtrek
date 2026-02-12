import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/daily_stats.dart';
import '../services/database_service.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class ChallengeRecordsScreen extends StatefulWidget {
  const ChallengeRecordsScreen({super.key});

  @override
  State<ChallengeRecordsScreen> createState() => _ChallengeRecordsScreenState();
}

class _ChallengeRecordsScreenState extends State<ChallengeRecordsScreen> with TickerProviderStateMixin {
  List<DailyActivity> _activities = [];
  Map<String, DailyWeather> _weathers = {};
  bool _isLoading = true;

  // Timeline 控制参数 (参考 HistoryOfEverything)
  double _scale = 1.0;
  double _scrollOffset = 0.0;
  double _lastScale = 1.0;
  
  // 渲染参数
  final double _basePixelsPerKm = 50.0; // 每一公里的基础像素高度
  late AnimationController _scrollController;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  Future<void> _loadData() async {
    final activities = await DatabaseService.instance.getAllActivities();
    activities.sort((a, b) => a.accumulatedDistanceKm.compareTo(b.accumulatedDistanceKm));

    Map<String, DailyWeather> weathers = {};
    for (var activity in activities) {
      final weather = await DatabaseService.instance.getWeatherByDate(activity.date);
      if (weather != null) weathers[activity.date] = weather;
    }

    if (mounted) {
      setState(() {
        _activities = activities;
        _weathers = weathers;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final size = MediaQuery.of(context).size;
    final totalDistance = _activities.isNotEmpty ? _activities.last.accumulatedDistanceKm : 100.0;
    final totalHeight = totalDistance * _basePixelsPerKm * _scale;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // 深色背景更具历史感
      body: Stack(
        children: [
          // 核心时间线渲染层
          GestureDetector(
            onScaleStart: (details) {
              _lastScale = _scale;
            },
            onScaleUpdate: (details) {
              setState(() {
                _scale = (_lastScale * details.scale).clamp(0.1, 20.0);
                _scrollOffset -= details.focalPointDelta.dy;
                _scrollOffset = _scrollOffset.clamp(0.0, math.max(0.0, totalHeight - size.height + 200));
              });
            },
            child: CustomPaint(
              size: size,
              painter: TimelinePainter(
                activities: _activities,
                weathers: _weathers,
                scale: _scale,
                offset: _scrollOffset,
                basePixelsPerKm: _basePixelsPerKm,
              ),
            ),
          ),
          
          // 顶部返回栏
          _buildHeader(),
          
          // 右侧缩放提示
          _buildZoomIndicator(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 100,
            padding: const EdgeInsets.only(top: 50, left: 10),
            color: Colors.black.withOpacity(0.3),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                ),
                const Text(
                  "时空长廊",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      right: 20,
      bottom: 100,
      child: Column(
        children: [
          const Icon(Icons.zoom_in, color: Colors.white30, size: 16),
          const SizedBox(height: 8),
          Container(
            width: 2,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(1),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: (1 - (_scale / 20.0)) * 100,
                  left: 0,
                  right: 0,
                  child: Container(height: 10, color: const Color(0xFF0097A7)),
                )
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Icon(Icons.zoom_out, color: Colors.white30, size: 16),
        ],
      ),
    );
  }
}

class TimelinePainter extends CustomPainter {
  final List<DailyActivity> activities;
  final Map<String, DailyWeather> weathers;
  final double scale;
  final double offset;
  final double basePixelsPerKm;

  TimelinePainter({
    required this.activities,
    required this.weathers,
    required this.scale,
    required this.offset,
    required this.basePixelsPerKm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width * 0.3;
    final Paint linePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;
    
    final Paint tickPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1.0;

    // 绘制主轴
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), linePaint);

    // 计算当前可见范围内的公里数
    final double startKm = offset / (basePixelsPerKm * scale);
    final double endKm = (offset + size.height) / (basePixelsPerKm * scale);

    // 1. 绘制公里刻度 (类似 HistoryOfEverything 的时间刻度)
    int step = scale > 5 ? 1 : scale > 2 ? 5 : scale > 0.5 ? 10 : 50;
    for (int km = (startKm ~/ step) * step; km <= endKm; km += step) {
      double y = km * basePixelsPerKm * scale - offset;
      if (y < 0 || y > size.height) continue;

      canvas.drawLine(Offset(centerX - 10, y), Offset(centerX + 10, y), tickPaint);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: "$km km",
          style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w200),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(centerX - 45, y - 6));
    }

    // 2. 绘制活动节点
    for (var activity in activities) {
      double y = activity.accumulatedDistanceKm * basePixelsPerKm * scale - offset;
      if (y < -100 || y > size.height + 100) continue;

      final weather = weathers[activity.date];
      
      // 节点圆点
      final nodePaint = Paint()
        ..color = const Color(0xFF0097A7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, y), 4 * math.min(scale, 2.0), nodePaint);
      canvas.drawCircle(Offset(centerX, y), 8 * math.min(scale, 2.0), Paint()..color = const Color(0xFF0097A7).withOpacity(0.2));

      // 信息气泡 (根据缩放显示不同详细程度)
      if (scale > 0.3) {
        _drawBubble(canvas, Offset(centerX + 30, y), activity, weather, scale);
      }
    }
  }

  void _drawBubble(Canvas canvas, Offset pos, DailyActivity activity, DailyWeather? weather, double scale) {
    final bubbleRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx, pos.dy - 35, 200, 70),
      const Radius.circular(12),
    );

    // 绘制气泡背景
    canvas.drawRRect(bubbleRRect, Paint()..color = Colors.white.withOpacity(0.05));
    
    // 日期文本
    final datePainter = TextPainter(
      text: TextSpan(
        text: activity.date,
        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    datePainter.paint(canvas, Offset(pos.dx + 12, pos.dy - 25));

    // 步数与里程
    final statsPainter = TextPainter(
      text: TextSpan(
        text: "${activity.steps} 步 | +${activity.distanceKm.toStringAsFixed(1)} km",
        style: const TextStyle(color: Color(0xFF0097A7), fontSize: 14, fontWeight: FontWeight.bold),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    statsPainter.paint(canvas, Offset(pos.dx + 12, pos.dy - 5));

    // 天气详细信息 (如果空间允许)
    if (weather != null && scale > 1.0) {
      final weatherPainter = TextPainter(
        text: TextSpan(
          text: "${weather.cityName} ${weather.currentTemp} | AQI: ${weather.aqi}",
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      weatherPainter.paint(canvas, Offset(pos.dx + 12, pos.dy + 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
