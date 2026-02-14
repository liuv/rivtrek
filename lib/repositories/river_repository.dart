// lib/repositories/river_repository.dart

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/river.dart';

/// 江河列表配置路径，与 [River] 模型字段对应。
const String _kRiversConfigPath = 'assets/json/rivers/rivers_config.json';

class RiverRepository {
  static final RiverRepository instance = RiverRepository._();
  RiverRepository._();

  List<River> _rivers = [];
  bool _loaded = false;

  /// 从配置文件加载江河列表并缓存。应用启动时需调用一次，之后 [getRiverById] / [getAvailableRivers] 使用缓存。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final String raw =
          await rootBundle.loadString(_kRiversConfigPath);
      final Map<String, dynamic> data = json.decode(raw) as Map<String, dynamic>;
      final List<dynamic> list = data['rivers'] as List<dynamic>? ?? [];
      final fromConfig = list
          .map((e) => River.fromJson(e as Map<String, dynamic>))
          .toList();
      // 从各河流 master JSON 读取 correction_coefficient，不依赖 config 手配
      final updated = <River>[];
      for (final r in fromConfig) {
        try {
          final masterRaw = await rootBundle.loadString(r.masterJsonPath);
          final master = json.decode(masterRaw) as Map<String, dynamic>;
          final coef = (master['correction_coefficient'] as num?)?.toDouble() ?? 1.0;
          updated.add(r.copyWith(correctionCoefficient: coef));
        } catch (_) {
          updated.add(r);
        }
      }
      _rivers = updated;
      _loaded = true;
    } catch (e, st) {
      // 配置缺失或格式错误时保留空列表，避免崩溃
      assert(() {
        // ignore: avoid_print
        print('RiverRepository.ensureLoaded failed: $e\n$st');
        return true;
      }());
    }
  }

  Future<List<River>> getAvailableRivers() async {
    await ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_rivers);
  }

  River? getRiverById(String id) {
    if (!_loaded) return null;
    try {
      return _rivers.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 按数字 id 检索，便于高效查找（如与数据库、外部系统对齐）。
  River? getRiverByNumericId(int numericId) {
    if (!_loaded) return null;
    try {
      return _rivers.firstWhere((r) => r.numericId == numericId);
    } catch (_) {
      return null;
    }
  }

  /// id → numeric_id，与 rivers_config.json 一致，供 POI 等按 config 查库。
  Map<String, int> getRiverSlugToNumericId() {
    if (!_loaded) return {};
    return {for (final r in _rivers) r.id: r.numericId};
  }

  /// numeric_id → id，与 rivers_config.json 一致。
  Map<int, String> getRiverNumericIdToSlug() {
    if (!_loaded) return {};
    return {for (final r in _rivers) r.numericId: r.id};
  }
}
