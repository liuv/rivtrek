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

      // 更新数据库
      double accumulatedDistance = 0.0;
      final allActivities = await DatabaseService.instance.getAllActivities();
      // 获取同步起点之前的最后一次累计里程
      final previousActivities = allActivities.where((a) => a.date.compareTo(DateFormat('yyyy-MM-dd').format(startDate)) < 0).toList();
      if (previousActivities.isNotEmpty) {
        previousActivities.sort((a, b) => b.date.compareTo(a.date));
        accumulatedDistance = previousActivities.first.accumulatedDistanceKm;
      }

      // 按日期顺序处理
      List<String> sortedDates = dailySteps.keys.toList()..sort();
      for (var date in sortedDates) {
        int steps = dailySteps[date]!;
        double distance = steps * _stepLengthKm;
        accumulatedDistance += distance;
        
        await DatabaseService.instance.saveActivity(DailyActivity(
          date: date,
          steps: steps,
          distanceKm: distance,
          accumulatedDistanceKm: accumulatedDistance,
        ));
      }
      debugPrint("Health Data Sync Completed for $days days.");
    } catch (e) {
      debugPrint("Health Data Sync Error: $e");
    }
  }

  /// 方案二：Android 传感器补偿 (Workmanager 调用)
  /// 直接读取硬件计步器，适合高频更新今日步数
  static Future<void> syncAndroidSensor() async {
    if (!Platform.isAndroid) return;

    Completer<void> completer = Completer();
    StreamSubscription? subscription;

    // 设定一个超时，因为后台任务不能运行太久
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.complete();
      }
    });

    subscription = Pedometer.stepCountStream.listen((event) async {
      final prefs = await SharedPreferences.getInstance();
      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      int hardwareTotal = event.steps;
      
      int base = prefs.getInt('base_steps_value') ?? hardwareTotal;
      
      // 处理重启：如果当前硬件总数小于基础值，说明手机重启过
      if (hardwareTotal < base) {
        base = hardwareTotal;
        await prefs.setInt('base_steps_value', base);
      }

      int todaySteps = hardwareTotal - base;
      
      // 检查日期切换
      String? lastSyncDate = prefs.getString('last_sync_date');
      if (lastSyncDate != today) {
        // 跨天了，把昨天的 base 结算掉
        await prefs.setString('last_sync_date', today);
        await prefs.setInt('base_steps_value', hardwareTotal);
        todaySteps = 0;
      }

      // 保存到数据库
      final allActivities = await DatabaseService.instance.getAllActivities();
      double totalHistory = allActivities
          .where((a) => a.date != today)
          .fold(0.0, (sum, item) => sum + item.distanceKm);

      await DatabaseService.instance.saveActivity(DailyActivity(
        date: today,
        steps: todaySteps,
        distanceKm: todaySteps * _stepLengthKm,
        accumulatedDistanceKm: totalHistory + (todaySteps * _stepLengthKm),
      ));

      debugPrint("Android Sensor Sync: $todaySteps steps.");
      subscription?.cancel();
      if (!completer.isCompleted) completer.complete();
    }, onError: (e) {
      debugPrint("Pedometer Error: $e");
      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }
}
