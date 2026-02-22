// lib/services/river_drift_service.dart
//
// 基于「虚拟源头时间戳」的河灯/漂流瓶仿真漂流。
// 不存当前位置，只存投放时的 timestamp + distanceAtKm，用河流时间轴按当前时间反推公里数。
// 流速加权：使漂流物经过整屏高度的平均时间约 30 秒。

import '../models/river_section.dart';

/// 河流一段：从 startKm 到 endKm，流速 speed km/h，从源头到本段起点需 timeToReachStart 小时
class RiverDriftSegment {
  final double startKm;
  final double endKm;
  final double lengthKm;
  final double speedKmh;
  final double timeToReachStartHours;

  RiverDriftSegment({
    required this.startKm,
    required this.endKm,
    required this.lengthKm,
    required this.speedKmh,
    required this.timeToReachStartHours,
  });
}

/// 河流漂流时间轴：由各 SubSection 预计算 timeToReachStart，并支持加权流速（整屏约 30 秒）
class RiverDriftTimeline {
  RiverDriftTimeline._({
    required this.segments,
    required this.totalLengthKm,
    required this.timeScale,
    required this.visibleRangeKm,
    required this.averageSpeedKmh,
  });

  final List<RiverDriftSegment> segments;
  final double totalLengthKm;
  /// 显示时间到「虚拟漂流时间」的倍数：1 秒显示时间 = timeScale 秒虚拟漂流
  final double timeScale;
  /// 一屏对应的河流公里数（用于 localY 映射与 30 秒目标）
  final double visibleRangeKm;
  final double averageSpeedKmh;

  /// 从有序的 SubSection 列表构建时间轴。
  /// [visibleRangeKm] 一屏显示的河道公里数，默认 3.0。
  /// [targetCrossScreenSeconds] 希望漂流物平均经过一屏的时间（秒），默认 30。
  static RiverDriftTimeline fromSubSections(
    List<SubSection> subSections, {
    double visibleRangeKm = 3.0,
    double targetCrossScreenSeconds = 30.0,
  }) {
    if (subSections.isEmpty) {
      return RiverDriftTimeline._(
        segments: [],
        totalLengthKm: 0,
        timeScale: 1,
        visibleRangeKm: visibleRangeKm,
        averageSpeedKmh: 0.5,
      );
    }

    double prevEndKm = 0;
    double timeToReachStartHours = 0;
    List<RiverDriftSegment> segs = [];
    double totalTimeHours = 0;

    for (final sub in subSections) {
      final endKm = sub.accumulatedLength;
      final lengthKm = endKm - prevEndKm;
      if (lengthKm <= 0) continue;
      final speedKmh = sub.baseFlowSpeed > 0 ? sub.baseFlowSpeed : 0.2;
      final segmentTimeHours = lengthKm / speedKmh;

      segs.add(RiverDriftSegment(
        startKm: prevEndKm,
        endKm: endKm,
        lengthKm: lengthKm,
        speedKmh: speedKmh,
        timeToReachStartHours: timeToReachStartHours,
      ));

      timeToReachStartHours += segmentTimeHours;
      totalTimeHours += segmentTimeHours;
      prevEndKm = endKm;
    }

    final totalLengthKm = prevEndKm;
    final averageSpeedKmh =
        totalTimeHours > 0 ? totalLengthKm / totalTimeHours : 0.5;
    // 希望：visibleRangeKm 在 targetCrossScreenSeconds 内漂完
    // 即 virtualTimeSeconds = visibleRangeKm / averageSpeedKmh * 3600
    // 显示 30 秒 = virtualTimeSeconds 的虚拟时间 => timeScale = virtualTimeSeconds / 30
    final virtualSecondsToCrossScreen =
        (visibleRangeKm / averageSpeedKmh) * 3600;
    final timeScale =
        virtualSecondsToCrossScreen / targetCrossScreenSeconds;

    return RiverDriftTimeline._(
      segments: segs,
      totalLengthKm: totalLengthKm,
      timeScale: timeScale,
      visibleRangeKm: visibleRangeKm,
      averageSpeedKmh: averageSpeedKmh,
    );
  }

  /// 从源头漂流到 distKm 所需时间（小时，按真实流速）
  double timeFromSourceHours(double distKm) {
    if (distKm <= 0) return 0;
    for (final seg in segments) {
      if (distKm <= seg.endKm) {
        final timeInSegment =
            (distKm - seg.startKm) / seg.speedKmh;
        return seg.timeToReachStartHours + timeInSegment;
      }
    }
    return segments.isEmpty
        ? 0
        : segments.last.timeToReachStartHours +
            segments.last.lengthKm / segments.last.speedKmh;
  }

  /// 给定「虚拟源头时间戳」（显示时间，秒）和当前时间（显示时间，秒），
  /// 返回漂流物当前公里数。
  double calculateCurrentDistance(
      double virtualSourceTimestampSec, double tNowSec) {
    final elapsedDisplaySec = tNowSec - virtualSourceTimestampSec;
    if (elapsedDisplaySec <= 0) {
      return 0;
    }
    final virtualElapsedSec = elapsedDisplaySec * timeScale;
    final virtualElapsedHours = virtualElapsedSec / 3600.0;

    for (final seg in segments) {
      final timeToReachEnd =
          seg.timeToReachStartHours + seg.lengthKm / seg.speedKmh;
      if (virtualElapsedHours < timeToReachEnd) {
        final remainingHours =
            virtualElapsedHours - seg.timeToReachStartHours;
        return seg.startKm + remainingHours * seg.speedKmh;
      }
    }
    return totalLengthKm;
  }

  /// 投放时：根据投放位置 distKm 和投放时间戳 dropTimestampSec（显示时间，秒），
  /// 计算并返回虚拟源头时间戳（显示时间，秒），用于存储与后续 calculateCurrentDistance。
  double calculateVirtualSourceTimestamp(
      double distKm, double dropTimestampSec) {
    final timeFromSourceH = timeFromSourceHours(distKm);
    final virtualSecondsFromSource = timeFromSourceH * 3600;
    return dropTimestampSec - virtualSecondsFromSource / timeScale;
  }

  /// 将公里数转为屏幕归一化 Y：-1 为屏顶（上游），1 为屏底（下游）。
  /// [visualCenterKm] 当前视口中心对应的公里数（如 _visualDistance）。
  double kmToLocalY(double currentKm, double visualCenterKm) {
    final half = visibleRangeKm / 2;
    if (half <= 0) return 0;
    return (currentKm - visualCenterKm) / half;
  }

  /// 视口公里范围 [minKm, maxKm]，用于过滤当前可见的漂流物
  (double, double) visibleRange(double visualCenterKm) {
    final half = visibleRangeKm / 2;
    return (
      (visualCenterKm - half).clamp(0.0, totalLengthKm),
      (visualCenterKm + half).clamp(0.0, totalLengthKm),
    );
  }
}
