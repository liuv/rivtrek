// 河流路径叠加层：在封面图或分享卡片上绘制路径（描边 + 外发光）+ 起点/终点/当前位置标记，可复用

import 'package:flutter/material.dart';
import '../models/river.dart';
import '../services/cover_path_service.dart';

/// 在封面或固定尺寸区域上叠加河流路径与当前位置。
/// [river] 用于加载 pointsJsonPath；[currentKm] 为挑战当前里程；[totalKm] 为挑战总长（如 river.totalLengthKm）。
/// 用进度比例 currentKm/totalKm 映射到路径上的位置，避免路径里程与挑战里程不一致导致点位偏移。
class RiverPathOverlay extends StatefulWidget {
  final Widget child;
  final River? river;
  final double currentKm;
  /// 挑战总里程（与 currentKm 同一套口径），用于按比例映射到路径；不传则退化为用 currentKm 直接当路径公里数
  final double? totalKm;
  final Color? pathColor;

  const RiverPathOverlay({
    super.key,
    required this.child,
    required this.river,
    this.currentKm = 0,
    this.totalKm,
    this.pathColor,
  });

  @override
  State<RiverPathOverlay> createState() => _RiverPathOverlayState();
}

class _RiverPathOverlayState extends State<RiverPathOverlay> {
  RiverCoverPathData? _pathData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  @override
  void didUpdateWidget(covariant RiverPathOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.river?.pointsJsonPath != widget.river?.pointsJsonPath) _loadPath();
  }

  Future<void> _loadPath() async {
    final path = widget.river?.pointsJsonPath;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() { _pathData = null; _loading = false; });
      return;
    }
    final data = await CoverPathService.loadPathForCover(path);
    if (mounted) setState(() { _pathData = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_loading && _pathData != null && _pathData!.normalizedPoints.length > 1)
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final themeColor = widget.pathColor ?? widget.river?.color ?? const Color(0xFF4FC3F7);
              final total = widget.totalKm ?? 0.0;
              final pathKm = _pathData!.totalKm;
              final pathFraction = (total > 0)
                  ? (widget.currentKm / total).clamp(0.0, 1.0)
                  : (pathKm > 0 ? (widget.currentKm / pathKm).clamp(0.0, 1.0) : 0.0);
              return CustomPaint(
                size: size,
                painter: _RiverPathOverlayPainter(
                  pathData: _pathData!,
                  pathFraction: pathFraction,
                  pathColor: themeColor,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _RiverPathOverlayPainter extends CustomPainter {
  final RiverCoverPathData pathData;
  /// 0–1，沿路径的进度，用于在屏幕路径上精确取点，保证白点在路径上
  final double pathFraction;
  final Color pathColor;

  _RiverPathOverlayPainter({
    required this.pathData,
    required this.pathFraction,
    required this.pathColor,
  });

  static const double _pathStrokeWidth = 2.2;
  static const double _strokeWidth = 3.0;
  static const double _glowWidth = 10.0;
  static const double _markerRadius = 6.0;
  static const double _markerStroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (pathData.normalizedPoints.length < 2) return;

    final path = _buildPath(size);
    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final glowPaint = Paint()
      ..color = pathColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _glowWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _pathStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 1. 外发光（先画最宽的一层）
    canvas.drawPath(path, glowPaint);
    // 2. 描边（白/浅色）
    canvas.drawPath(path, strokePaint);
    // 3. 主路径
    canvas.drawPath(path, fillPaint);

    final pts = pathData.normalizedPoints;
    final start = _normToScreen(pts.first, size);
    final end = _normToScreen(pts.last, size);

    _drawMarker(canvas, start, true);
    _drawMarker(canvas, end, true);
    // 沿屏幕路径按比例取点，保证当前位置白点精确落在路径上
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final length = metric.length;
      if (length > 0) {
        final offset = (pathFraction * length).clamp(0.0, length);
        final tangent = metric.getTangentForOffset(offset);
        if (tangent != null) _drawMarker(canvas, tangent.position, false);
      }
      break;
    }
  }

  Path _buildPath(Size size) {
    final p = Path();
    final pts = pathData.normalizedPoints;
    final o = _normToScreen(pts[0], size);
    p.moveTo(o.dx, o.dy);
    for (int i = 1; i < pts.length; i++) {
      final o2 = _normToScreen(pts[i], size);
      p.lineTo(o2.dx, o2.dy);
    }
    return p;
  }

  /// 等比例缩放、水平居中、垂直靠上：路径不遮挡封面底部（挑战者图像）
  Offset _normToScreen(Offset n, Size size) {
    final scale = size.width < size.height ? size.width : size.height;
    final offsetX = (size.width - scale) * 0.5;
    const offsetY = 0.0;
    return Offset(n.dx * scale + offsetX, n.dy * scale + offsetY);
  }

  void _drawMarker(Canvas canvas, Offset center, bool isStartOrEnd) {
    // 外圈描边（与路径同色或浅色）
    final outlinePaint = Paint()
      ..color = isStartOrEnd ? pathColor : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _markerStroke
      ..isAntiAlias = true;
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final r = _markerRadius;
    canvas.drawCircle(center, r, fillPaint);
    canvas.drawCircle(center, r, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _RiverPathOverlayPainter old) {
    return old.pathData != pathData ||
        old.pathFraction != pathFraction ||
        old.pathColor != pathColor;
  }
}
