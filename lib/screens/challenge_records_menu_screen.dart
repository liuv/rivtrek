import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivtrek/models/daily_stats.dart';
import 'package:rivtrek/repositories/river_repository.dart';
import 'package:rivtrek/services/database_service.dart';
import 'package:rivtrek/timeline/main_menu/menu_data.dart';
import 'package:rivtrek/timeline/main_menu/main_menu_section.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline_page.dart';

/// 挑战记录菜单：按河流分组展示，点击河流展开记录列表，点击某条记录进入时间线视图。
class ChallengeRecordsMenuScreen extends StatefulWidget {
  const ChallengeRecordsMenuScreen({super.key});

  @override
  State<ChallengeRecordsMenuScreen> createState() => _ChallengeRecordsMenuScreenState();
}

class _ChallengeRecordsMenuScreenState extends State<ChallengeRecordsMenuScreen> {
  List<MenuSectionData> _sections = [];
  bool _loading = true;
  List<DailyActivity>? _activities;
  List<DailyWeather>? _weathers;
  List<RiverEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activities = await DatabaseService.instance.getAllActivities();
    final weathers = await DatabaseService.instance.getAllWeather();
    final events = await DatabaseService.instance.getAllEvents();
    await RiverRepository.instance.ensureLoaded();

    final byRiver = <String, List<DailyActivity>>{};
    for (final a in activities) {
      byRiver.putIfAbsent(a.riverId, () => []).add(a);
    }
    for (final list in byRiver.values) {
      list.sort((a, b) => a.accumulatedDistanceKm.compareTo(b.accumulatedDistanceKm));
    }

    final sections = <MenuSectionData>[];
    for (final entry in byRiver.entries) {
      final river = RiverRepository.instance.getRiverById(entry.key);
      final section = MenuSectionData();
      section.label = river?.name ?? entry.key;
      section.textColor = river?.color ?? const Color(0xFF2196F3);
      section.backgroundColor = (river?.color ?? const Color(0xFF2196F3)).withOpacity(0.15);
      section.assetId = '';
      for (final a in entry.value) {
        section.items.add(MenuItemData.fromActivity(a, TimelineAxisMode.distanceKm));
      }
      sections.add(section);
    }
    sections.sort((a, b) => a.label.compareTo(b.label));

    if (mounted) {
      setState(() {
        _sections = sections;
        _activities = activities;
        _weathers = weathers;
        _events = events;
        _loading = false;
      });
    }
  }

  void _navigateToTimeline(MenuItemData item, TimelineAxisMode mode) {
    if (_activities == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimelinePage(
          activities: _activities,
          weathers: _weathers,
          events: _events,
          mode: mode,
          focusItem: item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '挑战记录',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0097A7)))
          : _sections.isEmpty
              ? Center(
                  child: Text(
                    '暂无记录',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  itemCount: _sections.length,
                  itemBuilder: (context, index) {
                    final section = _sections[index];
                    return Container(
                      margin: const EdgeInsets.only(top: 16),
                      child: MenuSection(
                        section.label,
                        section.backgroundColor,
                        section.textColor,
                        section.items,
                        (MenuItemData item) => _navigateToTimeline(item, TimelineAxisMode.distanceKm),
                        true,
                        assetId: section.assetId,
                      ),
                    );
                  },
                ),
    );
  }
}
