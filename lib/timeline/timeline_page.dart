
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivtrek/timeline/bloc_provider.dart';
import 'package:rivtrek/timeline/colors.dart';
import 'package:rivtrek/timeline/main_menu/main_menu.dart';
import 'package:rivtrek/timeline/main_menu/menu_data.dart';
import 'package:rivtrek/timeline/timeline/timeline_widget.dart';

import 'package:rivtrek/models/daily_stats.dart';

/// The app is wrapped by a [BlocProvider]. This allows the child widgets
/// to access other components throughout the hierarchy without the need
/// to pass those references around.
class TimelinePage extends StatelessWidget {
  const TimelinePage({Key? key, this.animationController, this.activities, this.weathers}) : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;
  final List<DailyWeather>? weathers;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return BlocProvider(
      activities: activities,
      weathers: weathers,
      child: MenuPage(animationController: animationController, activities: activities),
      platform: Theme.of(context).platform,
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({Key? key, this.animationController, this.activities}) : super(key: key);

  final AnimationController? animationController;
  final List<DailyActivity>? activities;

  @override
  Widget build(BuildContext context) {
    // 如果有活动数据，直接进入时间线
    if (activities != null && activities!.isNotEmpty) {
      final timeline = BlocProvider.getTimeline(context);
      // 创建一个聚焦到最后一个活动的 MenuItemData
      final focusItem = MenuItemData();
      focusItem.start = activities!.last.accumulatedDistanceKm;
      focusItem.end = activities!.last.accumulatedDistanceKm + 10.0;
      focusItem.label = "当前进度";
      
      return TimelineWidget(focusItem, timeline);
    }

    return Scaffold(
        appBar: null,
        body: MainMenuWidget(animationController: animationController),
    );
  }
}

// void main() => runApp(TimelineApp());