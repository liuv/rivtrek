import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import "package:flutter/services.dart" show rootBundle;
import 'package:rivtrek/models/daily_stats.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline/timeline_entry.dart';

/// Data container for the Section loaded in [MenuData.loadFromBundle()].
class MenuSectionData {
  String label = '';
  Color textColor = const Color(0x00FFFFFF);
  Color backgroundColor = const Color(0x00FFFFFF);
  String assetId = '';
  List<MenuItemData> items = <MenuItemData>[];
}

/// Data container for all the sub-elements of the [MenuSection].
class MenuItemData {
  String label = '';
  double start = 0;
  double end = 0;
  bool pad = false;
  double padTop = 0.0;
  double padBottom = 0.0;

  MenuItemData();
  /// When initializing this object from a [TimelineEntry], fill in the
  /// fields according to the [entry] provided. The entry in fact specifies
  /// a [label], a [start] and [end] times.
  /// Padding is built depending on the type of the [entry] provided.
  MenuItemData.fromEntry(TimelineEntry entry) {
    label = entry.label;

    /// Pad the edges of the screen.
    pad = true;
    TimelineAsset? asset = entry.asset;
    /// Extra padding for the top base don the asset size.
    padTop = asset == null ? 0.0 : asset.height * Timeline.AssetScreenScale;
    if (asset is TimelineAnimatedAsset) {
      padTop += asset.gap;
    }

    if (entry.type == TimelineEntryType.Era) {
      start = entry.start;
      end = entry.end;
    } else {
      /// No need to pad here as we are centering on a single item.
      double rangeBefore = double.maxFinite;
      for (TimelineEntry? prev = entry.previous;
          prev != null;
          prev = prev.previous) {
        double diff = entry.start - prev.start;
        if (diff > 0.0) {
          rangeBefore = diff;
          break;
        }
      }

      double rangeAfter = double.maxFinite;
      for (TimelineEntry? next = entry.next; next != null; next = next.next) {
        double diff = next.start - entry.start;
        if (diff > 0.0) {
          rangeAfter = diff;
          break;
        }
      }
      double range = min(rangeBefore, rangeAfter) / 2.0;
      if (!range.isFinite || range <= 0.0) {
        // Single-point or sparse data can produce maxFinite-derived Infinity here.
        // Keep a small finite viewport span to avoid breaking timeline scale.
        range = 1.0;
      }
      start = entry.start;
      end = entry.end + range;
    }
  }

  /// 从一条 [DailyActivity] 构建，用于挑战记录菜单点击后聚焦时间线。按 [axisMode] 设置 start/end。
  factory MenuItemData.fromActivity(DailyActivity activity, TimelineAxisMode axisMode) {
    final item = MenuItemData();
    item.label = '${activity.date} · +${activity.distanceKm.toStringAsFixed(1)} km（累计 ${activity.accumulatedDistanceKm.toStringAsFixed(1)} km）';
    item.pad = true;
    const double range = 2.0;
    if (axisMode == TimelineAxisMode.calendarDate) {
      final day = Timeline.dateStringToAxisDay(activity.date);
      item.start = day - range / 2;
      item.end = day + range / 2;
    } else {
      item.start = (activity.accumulatedDistanceKm - range / 2).clamp(0.0, double.infinity);
      item.end = activity.accumulatedDistanceKm + range / 2;
    }
    return item;
  }
}

/// This class has the sole purpose of loading the resources from storage and 
/// de-serializing the JSON file appropriately. 
/// 
/// `menu.json` contains an array of objects, each with:
/// * label - the title for the section
/// * background - the color on the section background
/// * color - the accent color for the menu section
/// * asset - the background Flare/Nima asset id that will play the section background
/// * items - an array of elements providing each the start and end times for that link
/// as well as the label to display in the [MenuSection].
class MenuData {
  List<MenuSectionData> sections = [];
  Future<bool> loadFromBundle(String filename) async {
    List<MenuSectionData> menu = <MenuSectionData>[];
    String data = await rootBundle.loadString(filename);
    List jsonEntries = json.decode(data) as List;
    for (dynamic entry in jsonEntries) {
      Map map = entry as Map;
      MenuSectionData menuSection = MenuSectionData();
      menu.add(menuSection);
      if (map.containsKey("label")) {
        menuSection.label = map["label"] as String;
      }
      if (map.containsKey("background")) {
        menuSection.backgroundColor = Color(int.parse(
                (map["background"] as String).substring(1, 7),
                radix: 16) +
            0xFF000000);
      }
      if (map.containsKey("color")) {
        menuSection.textColor = Color(
            int.parse((map["color"] as String).substring(1, 7), radix: 16) +
                0xFF000000);
      }
      if (map.containsKey("asset")) {
        menuSection.assetId = map["asset"] as String;
      }
      if (map.containsKey("items")) {
        List items = map["items"] as List;
        for (dynamic item in items) {
          Map itemMap = item as Map;
          MenuItemData itemData = MenuItemData();
          if (itemMap.containsKey("label")) {
            itemData.label = itemMap["label"] as String;
          }
          if (itemMap.containsKey("start")) {
            dynamic start = itemMap["start"];
            itemData.start = start is int ? start.toDouble() : start;
          }
          if (itemMap.containsKey("end")) {
            dynamic end = itemMap["end"];
            itemData.end = end is int ? end.toDouble() : end;
          }
          menuSection.items.add(itemData);
        }
      }
    }
    sections = menu;
    return true;
  }
}
