import 'dart:ui' as ui;

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
    double tickDistance = TickDistance.toDouble();
    double textTickDistance = TextTickDistance.toDouble();
    double gutterWidth = timeline.gutterWidth;

    if (timeline.isCalendarMode) {
      const List<int> minorCandidates = <int>[1, 2, 7, 14, 30, 90, 180, 365, 730];
      const List<int> majorCandidates = <int>[7, 14, 30, 90, 180, 365, 730, 1825];
      tickDistance = _pickTickStep(scale, minorCandidates, TickDistance.toDouble()).toDouble();
      textTickDistance =
          _pickTickStep(scale, majorCandidates, TextTickDistance.toDouble()).toDouble();
    } else {
      double scaledTickDistance = tickDistance * scale;
      if (scaledTickDistance > 2 * TickDistance) {
        while (scaledTickDistance > 2 * TickDistance && tickDistance >= 2.0) {
          scaledTickDistance /= 2.0;
          tickDistance /= 2.0;
          textTickDistance /= 2.0;
        }
      } else {
        while (scaledTickDistance < TickDistance) {
          scaledTickDistance *= 2.0;
          tickDistance *= 2.0;
          textTickDistance *= 2.0;
        }
      }
    }

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
      final double s = timeline.computeScale(timeline.renderStart, timeline.renderEnd);
      final double y1 = ((tickColors.first.start ?? 0.0) - timeline.renderStart) * s;
      final double y2 = ((tickColors.last.start ?? 0.0) - timeline.renderStart) * s;
      final ui.Paint paint = ui.Paint()
        ..shader = ui.Gradient.linear(
            ui.Offset(0.0, y1), ui.Offset(0.0, y2), colors, stops)
        ..style = ui.PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height), paint);
    } else {
      canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height),
          Paint()..color = const Color.fromRGBO(246, 246, 246, 0.95));
    }

    final double renderStart = timeline.renderStart;
    final double renderEnd = timeline.renderEnd;
    final int firstTick = (renderStart / tickDistance).floor() - 1;
    final int lastTick = (renderEnd / tickDistance).ceil() + 1;
    final int majorStep = textTickDistance.round().clamp(1, 1000000);

    for (int idx = firstTick; idx <= lastTick; idx++) {
      final double tickValue = idx * tickDistance;
      if (timeline.isDistanceMode && tickValue < 0) {
        continue;
      }
      final double y = offset.dy + (tickValue - renderStart) * scale;
      if (y < offset.dy - 20 || y > offset.dy + height + 20) {
        continue;
      }
      final int value = tickValue.round();
      final TickColors? colors = timeline.findTickColors(y);
      if (colors == null) {
        continue;
      }
      final bool isMajor = value % majorStep == 0;
      canvas.drawRect(
          Rect.fromLTWH(
              offset.dx + gutterWidth - (isMajor ? TickSize : SmallTickSize),
              y,
              isMajor ? TickSize : SmallTickSize,
              1.0),
          Paint()..color = (isMajor ? colors.long : colors.short) ?? Colors.transparent);

      if (!isMajor) {
        continue;
      }

      String label;
      if (timeline.isCalendarMode) {
        label = _formatCalendarLabel(tickValue, majorStep);
      } else if (timeline.isDistanceMode) {
        label = "${value.abs()} km";
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

  int _pickTickStep(double scale, List<int> candidates, double targetPixelGap) {
    for (final int step in candidates) {
      if (step * scale >= targetPixelGap) {
        return step;
      }
    }
    return candidates.last;
  }

  String _formatCalendarLabel(double axisDay, int majorStep) {
    final DateTime dt = Timeline.axisDayToDate(axisDay);
    final String y = dt.year.toString();
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    if (majorStep >= 365) {
      return y;
    }
    if (majorStep >= 30) {
      return "$y-$m";
    }
    return "$m-$d";
  }
}
