// lib/providers/challenge_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/river.dart';
import '../models/river_section.dart';
import '../repositories/river_repository.dart';
import '../services/database_service.dart';

class ChallengeProvider extends ChangeNotifier {
  River? _activeRiver;
  double _realDistance = 0.0;    // 真实的、由数据库驱动的进度（步数→累计里程）
  double _displayDistance = 0.0; // UI 显示的进度（非调试时与 real 同步，双指滑动时为虚拟值）
  List<SubSection> _allSubSections = [];
  SubSection? _currentSubSection;
  bool _isLoading = true;
  /// 双指滑动调试模式：为 true 时不随步数更新里程，仅随滑动；双击 tab 或重新打开 app 置为 false
  bool _debugSlideMode = false;

  // Getters
  River? get activeRiver => _activeRiver;
  double get realDistance => _realDistance;
  double get currentDistance => _displayDistance; // 页面显示这个
  bool get debugSlideMode => _debugSlideMode;
  List<SubSection> get allSubSections => _allSubSections;
  SubSection? get currentSubSection => _currentSubSection;
  bool get isLoading => _isLoading;

  ChallengeProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString('active_river_id') ?? 'yangtze';
    await switchRiver(activeId);
  }

  Future<void> switchRiver(String riverId) async {
    _isLoading = true;
    _debugSlideMode = false; // 每次切河流或冷启动都重置调试状态，按步数同步
    notifyListeners();

    final river = RiverRepository.instance.getRiverById(riverId);
    if (river == null) return;

    _activeRiver = river;
    
    // 1. 从数据库汇总当前河流的历史活动里程作为真实进度
    final allActivities = await DatabaseService.instance.getAllActivities();
    _realDistance = allActivities
        .where((a) => a.riverId == riverId)
        .fold(0.0, (sum, item) => sum + item.distanceKm);
    
    // 2. 默认显示真实进度
    _displayDistance = _realDistance;
    
    // 3. 持久化当前河流 ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_river_id', river.id);

    // 4. 加载河流描述数据
    await _loadRiverDetails(river);

    _isLoading = false;
    notifyListeners();
  }

  // 由 FlowController 调用，同步实时步数产生的累计里程（步数是当日，里程是累计）
  void syncRealDistance(double totalRealDistance) {
    _realDistance = totalRealDistance;
    if (!_debugSlideMode) {
      _displayDistance = _realDistance;
      _updateSubSection();
    }
    notifyListeners();
  }

  // 双指滑动：进入调试模式，仅更新虚拟显示，不再用步数更新里程
  void updateVirtualDistance(double newDistance) {
    if (_activeRiver == null) return;
    _debugSlideMode = true;
    _displayDistance = newDistance.clamp(0.0, _activeRiver!.totalLengthKm);
    _updateSubSection();
    notifyListeners();
  }

  // 双击底部「涉川」tab：退出调试模式，恢复为步数/里程同步显示
  void resetToRealDistance() {
    _debugSlideMode = false;
    _displayDistance = _realDistance;
    _updateSubSection();
    notifyListeners();
  }

  Future<void> _loadRiverDetails(River river) async {
    try {
      final String response = await rootBundle.loadString(river.masterJsonPath);
      final data = json.decode(response);
      List<SubSection> flatList = [];
      for (var s in data['challenge_sections']) {
        flatList.addAll(RiverSection.fromJson(s).subSections);
      }
      _allSubSections = flatList;
      _updateSubSection();
    } catch (e) {
      debugPrint("Error loading river details: $e");
    }
  }

  void _updateSubSection() {
    SubSection? found;
    for (var sub in _allSubSections) {
      if (_displayDistance <= sub.accumulatedLength) {
        found = sub;
        break;
      }
    }
    _currentSubSection = found ?? (_allSubSections.isNotEmpty ? _allSubSections.last : null);
  }
}
