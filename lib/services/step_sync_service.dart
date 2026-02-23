import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import '../models/daily_stats.dart';

class StepSyncService {
  static const double _stepLengthKm = 0.0007;

  /// 全局同步入口：根据平台选择不同的同步策略
  static Future<void> syncAll() async {
    if (Platform.isIOS) {
      await syncHealthData(days: 7);
    } else if (Platform.isAndroid) {
      // Android 双管齐下：既读 Health Connect 补全历史，也读传感器实时更新
      await syncHealthData(days: 7);
      await syncAndroidSensor();
    }
  }

  /// 方案一：从系统健康数据同步 (HealthKit / Health Connect)
  /// 支持多日补全，防止用户某几天没打开 App
  static Future<void> syncHealthData({int days = 3}) async {
    Health health = Health();
    final types = [HealthDataType.STEPS];
    final permissions = [HealthDataAccess.READ];

    try {
      bool authorized = await health.requestAuthorization(types, permissions: permissions);
      if (!authorized) return;

      final now = DateTime.now();
      // 从 N 天前的凌晨开始同步
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
      
      // 获取所有步数数据点
      List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
        startTime: startDate,
        endTime: now,
        types: types,
      );

      debugPrint("Health Connect: got ${healthData.length} raw data points for STEPS.");

      // 按日期分组统计步数
      Map<String, int> dailySteps = {};
      for (var point in healthData) {
        final dateStr = DateFormat('yyyy-MM-dd').format(point.dateFrom);
        int value = 0;
        if (point.value is NumericHealthValue) {
          value = (point.value as NumericHealthValue).numericValue.toInt();
        }
        dailySteps[dateStr] = (dailySteps[dateStr] ?? 0) + value;
      }

      // 若明细为空，Android 上尝试用「区间总步数」拉取今日步数（部分设备只提供聚合结果）
      if (dailySteps.isEmpty && Platform.isAndroid) {
        final todayStart = DateTime(now.year, now.month, now.day);
        int? totalToday = await health.getTotalStepsInInterval(todayStart, now);
        if (totalToday != null && totalToday > 0) {
          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          dailySteps[todayStr] = totalToday;
          debugPrint("Health Connect: getTotalStepsInInterval(today) = $totalToday.");
        }
      }

      if (dailySteps.isEmpty) {
        debugPrint("Health Data Sync: no step data from Health Connect (0 points, 0 daily).");
      } else {
        debugPrint("Health Data Sync: dailySteps = $dailySteps");
      }

      final prefs = await SharedPreferences.getInstance();
      final String riverId = prefs.getString('active_river_id') ?? 'yangtze';
      final String todayStr = DateFormat('yyyy-MM-dd').format(now);

      const kChallengeStartDate = 'challenge_start_date';
      String challengeStartDate = prefs.getString(kChallengeStartDate) ?? '';

      final allActivities = await DatabaseService.instance.getAllActivities();
      final activitiesForRiver = allActivities
          .where((a) => a.riverId == riverId)
          .toList();

      // 安装对齐：仅当「当前河流在 DB 中没有任何活动」时从今天起算（全新安装/卸载重装）。
      // 升级安装时 DB 已有活动，activitiesForRiver 非空，不会进此分支，保留原有 challenge_start_date 与历史数据。
      if (activitiesForRiver.isEmpty) {
        challengeStartDate = todayStr;
        await prefs.setString(kChallengeStartDate, todayStr);
        if (kDebugMode) {
          debugPrint(
              "Health Data Sync: no activities for river, set challenge_start_date=$todayStr (fresh/reinstall).");
        }
      } else if (challengeStartDate.isEmpty) {
        challengeStartDate = todayStr;
        await prefs.setString(kChallengeStartDate, todayStr);
        debugPrint("Health Data Sync: challenge_start_date set to $challengeStartDate (first run, legacy).");
      }

      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final previousActivities = allActivities
          .where((a) =>
              a.riverId == riverId &&
              a.date.compareTo(startDateStr) < 0 &&
              a.date.compareTo(challengeStartDate) >= 0)
          .toList();
      double accumulatedDistance = 0.0;
      if (previousActivities.isNotEmpty) {
        previousActivities.sort((a, b) => b.date.compareTo(a.date));
        accumulatedDistance = previousActivities.first.accumulatedDistanceKm;
      }

      // 只处理 >= 挑战起始日的日期
      List<String> sortedDates = dailySteps.keys
          .where((d) => d.compareTo(challengeStartDate) >= 0)
          .toList()
        ..sort();

      // 冲突策略：同日期已存在时取 max(已有步数, 健康数据步数)，避免被较小值覆盖丢失进度
      final existingByDate = {
        for (var a in activitiesForRiver) a.date: a,
      };
      for (var date in sortedDates) {
        final healthSteps = dailySteps[date]!;
        final existing = existingByDate[date];
        final steps = existing != null
            ? (healthSteps > existing.steps ? healthSteps : existing.steps)
            : healthSteps;
        final distance = steps * _stepLengthKm;
        accumulatedDistance += distance;
        await DatabaseService.instance.saveActivity(DailyActivity(
          date: date,
          steps: steps,
          distanceKm: distance,
          accumulatedDistanceKm: accumulatedDistance,
          riverId: riverId,
        ));
      }
      if (sortedDates.isNotEmpty) {
        await prefs.setString('last_steps_source', 'health_connect');
      }
      debugPrint("Health Data Sync Completed for $days days.");
    } catch (e) {
      debugPrint("Health Data Sync Error: $e");
    }
  }

  /// 方案二：Android 传感器计步（日界基线法，对齐 Google Fit 思路）
  /// - 今日步数 = 当前硬件累计 - 今日 0 点基线；今日基线 = 昨日最后一次同步时的累计值。
  /// - 依赖后台：WorkManager 每 15 分钟跑一次（不依赖网络），确保日界前至少跑一次，避免「上午 10 点后步数被记到明天」和漏天。
  /// - 用户需在「应用设置」中授权忽略电池优化/自启动，否则厂商可能杀掉后台导致漏天。
  /// - [currentHardwareSteps] 若由外部传入（如 FlowController 的 pedometer 回调），则直接用该值写库并返回，避免二次订阅导致收不到事件、页面不刷新。
  static Future<void> syncAndroidSensor({int? currentHardwareSteps}) async {
    if (!Platform.isAndroid) return;

    if (currentHardwareSteps != null) {
      try {
        await _writeSensorStepsToDb(currentHardwareSteps);
      } catch (e) {
        debugPrint("Android Sensor Sync (with steps) Error: $e");
      }
      return;
    }

    final completer = Completer<void>();
    StreamSubscription<StepCount>? subscription;
    var completed = false;
    void finish() {
      if (completed) return;
      completed = true;
      subscription?.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    Timer(const Duration(seconds: 10), finish);

    subscription = Pedometer.stepCountStream.listen((event) async {
      try {
        await _writeSensorStepsToDb(event.steps);
        debugPrint("Android Sensor Sync: today from stream (cumulative=${event.steps})");
      } catch (e) {
        debugPrint("Android Sensor Sync Error: $e");
      } finally {
        finish();
      }
    }, onError: (e) {
      debugPrint("Pedometer Error: $e");
      finish();
    });

    return completer.future;
  }

  static Future<void> _writeSensorStepsToDb(int hardwareTotal) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    const kLastSyncDate = 'sensor_last_sync_date';
    const kLastDayEndCumulative = 'sensor_last_day_end_cumulative';
    const kStepsAtDayStart = 'sensor_steps_at_day_start';

    if (prefs.getString(kLastSyncDate) == null &&
        prefs.getString('last_sync_date') != null &&
        prefs.getInt('base_steps_value') != null) {
      await prefs.setString(kLastSyncDate, prefs.getString('last_sync_date')!);
      await prefs.setInt(kLastDayEndCumulative, prefs.getInt('base_steps_value')!);
      await prefs.setInt(kStepsAtDayStart, prefs.getInt('base_steps_value')!);
    }

    String? lastSyncDate = prefs.getString(kLastSyncDate);
    int lastDayEnd = prefs.getInt(kLastDayEndCumulative) ?? hardwareTotal;
    int stepsAtDayStart = prefs.getInt(kStepsAtDayStart) ?? hardwareTotal;

    int todaySteps;
    if (lastSyncDate == null) {
      stepsAtDayStart = hardwareTotal;
      lastSyncDate = today;
      lastDayEnd = hardwareTotal;
      todaySteps = 0;
      await prefs.setString(kLastSyncDate, today);
      await prefs.setInt(kLastDayEndCumulative, hardwareTotal);
      await prefs.setInt(kStepsAtDayStart, hardwareTotal);
    } else if (lastSyncDate != today) {
      stepsAtDayStart = lastDayEnd;
      if (hardwareTotal < stepsAtDayStart) stepsAtDayStart = hardwareTotal;
      todaySteps = (hardwareTotal - stepsAtDayStart).clamp(0, 0x7FFFFFFF);
      lastSyncDate = today;
      lastDayEnd = hardwareTotal;
      await prefs.setString(kLastSyncDate, today);
      await prefs.setInt(kLastDayEndCumulative, hardwareTotal);
      await prefs.setInt(kStepsAtDayStart, stepsAtDayStart);
    } else {
      if (hardwareTotal < stepsAtDayStart) {
        stepsAtDayStart = hardwareTotal;
        await prefs.setInt(kStepsAtDayStart, hardwareTotal);
      }
      todaySteps = (hardwareTotal - stepsAtDayStart).clamp(0, 0x7FFFFFFF);
      lastDayEnd = hardwareTotal;
      await prefs.setInt(kLastDayEndCumulative, hardwareTotal);
    }

    final String riverId = prefs.getString('active_river_id') ?? 'yangtze';
    final allActivities = await DatabaseService.instance.getAllActivities();
    final double totalHistory = allActivities
        .where((a) => a.date != today && a.riverId == riverId)
        .fold(0.0, (sum, item) => sum + item.distanceKm);

    // 冲突策略：今日若已有记录（如 Health 已写），取步数较大值，不丢失进度
    final existingToday = allActivities
        .where((a) => a.date == today && a.riverId == riverId)
        .firstOrNull;
    final stepsToWrite = existingToday != null
        ? (todaySteps > existingToday.steps ? todaySteps : existingToday.steps)
        : todaySteps;
    final distanceToWrite = stepsToWrite * _stepLengthKm;

    await DatabaseService.instance.saveActivity(DailyActivity(
      date: today,
      steps: stepsToWrite,
      distanceKm: distanceToWrite,
      accumulatedDistanceKm: totalHistory + distanceToWrite,
      riverId: riverId,
    ));
    await prefs.setString('last_steps_source', 'sensor');

    debugPrint("Android Sensor Sync: today=$stepsToWrite (cumulative=$hardwareTotal, baseline=$stepsAtDayStart)");
  }
}
