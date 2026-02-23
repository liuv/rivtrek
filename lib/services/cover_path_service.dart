// 封面路径数据：从河流 points JSON 加载、下采样至约 100 点、归一化到 0–1，供封面与分享绘制使用

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'geo_service.dart';

const int kCoverPathTargetPoints = 100;
const double kCoverPathPadding = 0.08;

/// 归一化后的封面路径数据（约 100 点，坐标 0–1）
class RiverCoverPathData {
  final List<Offset> normalizedPoints;
  final List<double> cumulativeDistances;
  final double totalKm;

  RiverCoverPathData({
    required this.normalizedPoints,
    required this.cumulativeDistances,
    required this.totalKm,
  });
}

class CoverPathService {
  static final Map<String, RiverCoverPathData> _cache = {};

  /// 使用 [pointsJsonPath] 作为缓存 key，避免同一河流重复解析
  static Future<RiverCoverPathData?> loadPathForCover(String pointsJsonPath) async {
    if (_cache.containsKey(pointsJsonPath)) return _cache[pointsJsonPath];

    try {
      final data = await GeoService.loadRiverPointsData(pointsJsonPath);
      final flat = <List<double>>[];
      for (var s in data.sectionsPoints) {
        for (var p in s) flat.add([p[0], p[1]]);
      }
      if (flat.isEmpty) return null;

      final downsampled = _downsample(flat, kCoverPathTargetPoints);
      final dists = _cumulativeDistances(downsampled);
      final totalKm = dists.isEmpty ? 0.0 : dists.last;
      final normalized = _normalizeToUnit(downsampled);

      final pathData = RiverCoverPathData(
        normalizedPoints: normalized,
        cumulativeDistances: dists,
        totalKm: totalKm,
      );
      _cache[pointsJsonPath] = pathData;
      return pathData;
    } catch (e) {
      return null;
    }
  }

  /// 根据当前里程 (km) 在路径上插值得到归一化坐标 (0–1)
  static Offset? getPositionOnPath(RiverCoverPathData data, double currentKm) {
    if (data.normalizedPoints.isEmpty || data.cumulativeDistances.isEmpty) return null;
    if (currentKm <= 0) return data.normalizedPoints.first;
    if (currentKm >= data.totalKm) return data.normalizedPoints.last;

    final dists = data.cumulativeDistances;
    int i = 0;
    while (i < dists.length - 1 && dists[i + 1] < currentKm) i++;
    if (i >= dists.length - 1) return data.normalizedPoints.last;

    final t = (currentKm - dists[i]) / (dists[i + 1] - dists[i]).clamp(0.0, 1.0);
    final a = data.normalizedPoints[i];
    final b = data.normalizedPoints[i + 1];
    return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  }

  static List<List<double>> _downsample(List<List<double>> points, int targetCount) {
    if (points.length <= targetCount) return List.from(points);
    final indices = <int>[0];
    for (int i = 1; i < targetCount; i++) {
      indices.add((i * (points.length - 1) / (targetCount - 1)).round().clamp(0, points.length - 1));
    }
    indices.add(points.length - 1);
    final seen = <int>{};
    final out = <List<double>>[];
    for (final i in indices) {
      if (seen.add(i)) out.add(points[i]);
    }
    return out;
  }

  static List<double> _cumulativeDistances(List<List<double>> points) {
    final dists = <double>[0.0];
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1], p1 = points[i];
      final km = _haversineKm(p0[1], p0[0], p1[1], p1[0]);
      dists.add(dists.last + km);
    }
    return dists;
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static List<Offset> _normalizeToUnit(List<List<double>> points) {
    if (points.isEmpty) return [];
    double minLng = points[0][0], maxLng = points[0][0], minLat = points[0][1], maxLat = points[0][1];
    for (var p in points) {
      if (p[0] < minLng) minLng = p[0];
      if (p[0] > maxLng) maxLng = p[0];
      if (p[1] < minLat) minLat = p[1];
      if (p[1] > maxLat) maxLat = p[1];
    }
    final pad = kCoverPathPadding;
    final spanLng = (maxLng - minLng).clamp(1e-6, double.infinity);
    final spanLat = (maxLat - minLat).clamp(1e-6, double.infinity);
    final out = <Offset>[];
    for (var p in points) {
      final x = (p[0] - minLng) / spanLng * (1 - 2 * pad) + pad;
      final y = 1.0 - (p[1] - minLat) / spanLat * (1 - 2 * pad) - pad;
      out.add(Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)));
    }
    return out;
  }
}
