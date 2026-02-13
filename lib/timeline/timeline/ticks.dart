import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline/timeline_entry.dart';
import 'package:rivtrek/timeline/timeline/timeline_utils.dart';

/// This class is used by the [TimelineRenderWidget] to render the ticks on the left side of the screen.
/// 
/// It has a single [paint()] method that's called within [TimelineRenderObject.paint()].
class Ticks {
  /// The following `const` variables are used to properly align, pad and layout the ticks 
  /// on the left side of the timeline.
  static const double Margin = 20.0;
  static const double Width = 40.0;
  static const double LabelPadLeft = 5.0;
  static const double LabelPadRight = 1.0;
  static const int TickDistance = 16;
  static const int TextTickDistance = 64;
  static const double TickSize = 15.0;
  static const double SmallTickSize = 5.0;

  /// Other than providing the [PaintingContext] to allow the ticks to paint themselves,
  /// other relevant sizing information is passed to this `paint()` method, as well as 
  /// a reference to the [Timeline].
  void paint(PaintingContext context, Offset offset, double translation,
      double scale, double height, Timeline timeline) {
    final Canvas canvas = context.canvas;
    final double gutterWidth = timeline.gutterWidth;
    final double renderStart = timeline.renderStart;
    final double renderEnd = timeline.renderEnd;
    final double range = renderEnd - renderStart;

    // 防御性保护：避免初始/异常 viewport 造成 NaN/Infinity 进入绘制 API。
    if (!scale.isFinite ||
        scale == 0.0 ||
        !height.isFinite ||
        height <= 0.0 ||
        !gutterWidth.isFinite ||
        gutterWidth <= 0.0 ||
        !renderStart.isFinite ||
        !renderEnd.isFinite ||
        !range.isFinite ||
        range.abs() < 1e-9) {
      return;
    }

    // 按缩放动态选取“次刻度步长”，而不是固定除2/乘2，避免标签稀疏失真。
    double tickDistance;
    if (timeline.isCalendarMode) {
      tickDistance = _pickDoubleStep(scale, const <double>[
        1, 2, 3, 7, 14, 30, 60, 90, 180, 365
      ], 16.0);
    } else if (timeline.isDistanceMode) {
      tickDistance = _pickDoubleStep(scale, const <double>[
        0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100
      ], 16.0);
    } else {
      tickDistance = _pickDoubleStep(
          scale, const <double>[1, 2, 5, 10, 20, 50, 100, 200, 500], 16.0);
    }
    final double scaledTickDistance = tickDistance * scale;
    final int majorEvery =
        math.max(1, (72.0 / math.max(1.0, scaledTickDistance)).round());
    final double majorDistance = tickDistance * majorEvery;

    final List<TickColors> tickColors = timeline.tickColors;
    if (tickColors.isNotEmpty) {
      double rangeStart = (tickColors.first.start ?? 0.0);
      double rangeEnd = (tickColors.last.start ?? 0.0);
      double range = rangeEnd - rangeStart;
      if (range == 0) range = 1.0;
      final List<ui.Color> colors = <ui.Color>[];
      final List<double> stops = <double>[];
      for (TickColors bg in tickColors) {
        colors.add(bg.background ?? Colors.transparent);
        stops.add(((bg.start ?? 0.0) - rangeStart) / range);
      }
      final double s = timeline.computeScale(renderStart, renderEnd);
      final double y1 = ((tickColors.first.start ?? 0.0) - renderStart) * s;
      final double y2 = ((tickColors.last.start ?? 0.0) - renderStart) * s;
      if (s.isFinite && y1.isFinite && y2.isFinite) {
        final ui.Paint paint = ui.Paint()
          ..shader = ui.Gradient.linear(
              ui.Offset(0.0, y1), ui.Offset(0.0, y2), colors, stops)
          ..style = ui.PaintingStyle.fill;
        canvas.drawRect(
            Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height), paint);
      } else {
        canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height),
            Paint()..color = const Color.fromRGBO(246, 246, 246, 0.95));
      }
    } else {
      canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height),
          Paint()..color = const Color.fromRGBO(246, 246, 246, 0.95));
    }

    final int firstTick = (renderStart / tickDistance).floor() - 1;
    final int lastTick = (renderEnd / tickDistance).ceil() + 1;

    for (int idx = firstTick; idx <= lastTick; idx++) {
      final double tickValue = idx * tickDistance;
      if (timeline.isDistanceMode && tickValue < 0) {
        continue;
      }
      final double y = offset.dy + (tickValue - renderStart) * scale;
      if (!y.isFinite) {
        continue;
      }
      if (y < offset.dy - 20 || y > offset.dy + height + 20) {
        continue;
      }
      final TickColors? colors = timeline.findTickColors(y);
      if (colors == null) {
        continue;
      }
      final bool isMajor = idx % majorEvery == 0;
      final double x = offset.dx +
          gutterWidth -
          (isMajor ? TickSize : SmallTickSize);
      if (!x.isFinite) {
        continue;
      }
      canvas.drawRect(
          Rect.fromLTWH(
              x,
              y,
              isMajor ? TickSize : SmallTickSize,
              1.0),
          Paint()..color = (isMajor ? colors.long : colors.short) ?? Colors.transparent);

      if (!isMajor) {
        continue;
      }

      String label;
      if (timeline.isCalendarMode) {
        label = _formatCalendarLabel(tickValue, majorDistance);
      } else if (timeline.isDistanceMode) {
        label = "${_formatDistance(tickValue.abs())} km";
      } else {
        label = TimelineEntry.formatYears(tickValue);
      }
      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.end, fontFamily: "Roboto", fontSize: 10.0))
        ..pushStyle(ui.TextStyle(color: colors.text ?? Colors.transparent))
        ..addText(label);
      final ui.Paragraph tickParagraph = builder.build();
      tickParagraph.layout(ui.ParagraphConstraints(
          width: gutterWidth - LabelPadLeft - LabelPadRight));
      canvas.drawParagraph(
          tickParagraph,
          Offset(offset.dx + LabelPadLeft - LabelPadRight,
              y - tickParagraph.height - 5));
    }
  }

  double _pickDoubleStep(
      double scale, List<double> candidates, double targetPixelGap) {
    for (final double step in candidates) {
      if (step * scale >= targetPixelGap) {
        return step;
      }
    }
    return candidates.last;
  }

  String _formatCalendarLabel(double axisDay, double majorDistanceInDays) {
    final DateTime dt = Timeline.axisDayToDate(axisDay);
    final String y = dt.year.toString();
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    if (majorDistanceInDays >= 365) {
      return y;
    }
    if (majorDistanceInDays >= 30) {
      return "$y-$m";
    }
    return "$m-$d";
  }

  String _formatDistance(double value) {
    if (value >= 10) {
      return value.round().toString();
    }
    if (value >= 1) {
      return value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    }
    return value.toStringAsFixed(1);
  }
}
