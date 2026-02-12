
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
      this.mode = TimelineAxisMode.distanceKm})
      : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;
  final List<DailyWeather>? weathers;
  final List<RiverEvent>? events;
  final TimelineAxisMode mode;

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
          mode: mode),
      platform: Theme.of(context).platform,
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({Key? key, this.animationController, this.activities, required this.mode}) : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;
  final TimelineAxisMode mode;

  @override
  Widget build(BuildContext context) {
    // 挑战记录入口始终直达时间线（无数据时展示空态轴）。
    if (activities != null) {
      final timeline = BlocProvider.getTimeline(context);
      // 创建一个聚焦到最后一个活动的 MenuItemData
      final focusItem = MenuItemData();
      if (activities!.isNotEmpty) {
        if (mode == TimelineAxisMode.calendarDate) {
          final sorted = List<DailyActivity>.from(activities!)
            ..sort((a, b) => Timeline.dateStringToAxisDay(a.date)
                .compareTo(Timeline.dateStringToAxisDay(b.date)));
          final double lastDay = Timeline.dateStringToAxisDay(sorted.last.date);
          focusItem.start = lastDay - 30.0;
          focusItem.end = lastDay + 3.0;
          focusItem.label = "最近记录";
        } else {
          final sorted = List<DailyActivity>.from(activities!)
            ..sort((a, b) => a.accumulatedDistanceKm.compareTo(b.accumulatedDistanceKm));
          final double lastDistance = sorted.last.accumulatedDistanceKm;
          focusItem.start = (lastDistance - 25.0).clamp(0.0, double.maxFinite);
          focusItem.end = lastDistance + 10.0;
          focusItem.label = "当前进度";
        }
      } else {
        focusItem.start = 0.0;
        focusItem.end = 30.0;
        focusItem.label = "挑战记录";
      }
      
      return TimelineWidget(focusItem, timeline);
    }

    return Scaffold(
        appBar: null,
        body: MainMenuWidget(animationController: animationController),
    );
  }
}

// void main() => runApp(TimelineApp());