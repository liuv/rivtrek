// lib/providers/challenge_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/river.dart';
import '../models/river_section.dart';
import '../repositories/river_repository.dart';

class ChallengeProvider extends ChangeNotifier {
  River? _activeRiver;
  double _currentDistance = 0.0;
  List<SubSection> _allSubSections = [];
  SubSection? _currentSubSection;
  bool _isLoading = true;

  // Getters
  River? get activeRiver => _activeRiver;
  double get currentDistance => _currentDistance;
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
    _isLoading = false;
    notifyListeners();
  }

  Future<void> switchRiver(String riverId) async {
    _isLoading = true;
    notifyListeners();

    final river = RiverRepository.instance.getRiverById(riverId);
    if (river == null) return;

    _activeRiver = river;
    
    // 加载进度
    final prefs = await SharedPreferences.getInstance();
    _currentDistance = prefs.getDouble('progress_${river.id}') ?? 0.0;
    
    // 持久化当前河流 ID
    await prefs.setString('active_river_id', river.id);

    // 加载河流具体数据
    await _loadRiverDetails(river);

    _isLoading = false;
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

  void updateDistance(double newDistance) async {
    if (_activeRiver == null) return;
    
    _currentDistance = newDistance.clamp(0.0, _activeRiver!.totalLengthKm);
    _updateSubSection();
    
    // 异步保存进度
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('progress_${_activeRiver!.id}', _currentDistance);
    
    notifyListeners();
  }

  void _updateSubSection() {
    SubSection? found;
    for (var sub in _allSubSections) {
      if (_currentDistance <= sub.accumulatedLength) {
        found = sub;
        break;
      }
    }
    _currentSubSection = found ?? (_allSubSections.isNotEmpty ? _allSubSections.last : null);
  }
}
