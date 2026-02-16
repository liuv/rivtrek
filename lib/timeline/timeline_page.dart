
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivtrek/timeline/bloc_provider.dart';
import 'package:rivtrek/timeline/main_menu/main_menu.dart';
import 'package:rivtrek/timeline/main_menu/menu_data.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline/timeline_widget.dart';

import 'package:rivtrek/models/daily_stats.dart';

/// The app is wrapped by a [BlocProvider]. This allows the child widgets
/// to access other components throughout the hierarchy without the need
/// to pass those references around.
class TimelinePage extends StatelessWidget {
  const TimelinePage(
      {Key? key,
      this.animationController,
      this.activities,
      this.weathers,
      this.events,
      this.mode = TimelineAxisMode.distanceKm,
      this.focusItem})
      : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;
  final List<DailyWeather>? weathers;
  final List<RiverEvent>? events;
  final TimelineAxisMode mode;
  /// 从挑战记录菜单进入时传入，用于聚焦到某条记录；未传则聚焦到最近进度。
  final MenuItemData? focusItem;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return BlocProvider(
      activities: activities,
      weathers: weathers,
      events: events,
      mode: mode,
      child: MenuPage(
          animationController: animationController,
          activities: activities,
          weathers: weathers,
          events: events,
          mode: mode,
          focusItem: focusItem),
      platform: Theme.of(context).platform,
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({
    Key? key,
    this.animationController,
    this.activities,
    this.weathers,
    this.events,
    required this.mode,
    this.focusItem,
  }) : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;
  final List<DailyWeather>? weathers;
  final List<RiverEvent>? events;
  final TimelineAxisMode mode;
  final MenuItemData? focusItem;

  @override
  Widget build(BuildContext context) {
    // 挑战记录入口：有数据则直接进时间线（带可选 focusItem）；无数据时展示空态轴。
    if (activities != null) {
      final timeline = BlocProvider.getTimeline(context);
      MenuItemData effectiveFocus = focusItem ?? MenuItemData();
      if (focusItem == null && activities!.isNotEmpty) {
        if (mode == TimelineAxisMode.calendarDate) {
          final sorted = List<DailyActivity>.from(activities!)
            ..sort((a, b) => Timeline.dateStringToAxisDay(a.date)
                .compareTo(Timeline.dateStringToAxisDay(b.date)));
          final double lastDay = Timeline.dateStringToAxisDay(sorted.last.date);
          effectiveFocus.start = lastDay - 30.0;
          effectiveFocus.end = lastDay + 3.0;
          effectiveFocus.label = "最近记录";
        } else {
          final sorted = List<DailyActivity>.from(activities!)
            ..sort((a, b) => a.accumulatedDistanceKm.compareTo(b.accumulatedDistanceKm));
          final double lastDistance = sorted.last.accumulatedDistanceKm;
          effectiveFocus.start = (lastDistance - 25.0).clamp(0.0, double.maxFinite);
          effectiveFocus.end = lastDistance + 10.0;
          effectiveFocus.label = "当前进度";
        }
      } else if (focusItem == null) {
        effectiveFocus.start = 0.0;
        effectiveFocus.end = 30.0;
        effectiveFocus.label = "挑战记录";
      }

      return TimelineWidget(
        effectiveFocus,
        timeline,
        activities: activities,
        weathers: weathers,
        events: events,
        axisMode: mode,
        onSwitchAxisMode: (newMode) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TimelinePage(
                activities: activities,
                weathers: weathers,
                events: events,
                mode: newMode,
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
        appBar: null,
        body: MainMenuWidget(animationController: animationController),
    );
  }
}

// void main() => runApp(TimelineApp());