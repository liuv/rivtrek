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

    double bottom = height;
    double tickDistance = TickDistance.toDouble();
    double textTickDistance = TextTickDistance.toDouble();
    /// The width of the left panel can expand and contract if the favorites-view is activated,
    /// by pressing the button on the top-right corner of the timeline.
    double gutterWidth = timeline.gutterWidth;

    /// Calculate spacing based on current scale.
    double scaledTickDistance;
    if (timeline.isCalendarMode) {
      const List<int> minorCandidates = <int>[1, 2, 7, 14, 30, 90, 180, 365, 730];
      const List<int> majorCandidates = <int>[7, 14, 30, 90, 180, 365, 730, 1825];
      tickDistance =
          _pickTickStep(scale, minorCandidates, TickDistance.toDouble())
              .toDouble();
      textTickDistance =
          _pickTickStep(scale, majorCandidates, TextTickDistance.toDouble())
              .toDouble();
      scaledTickDistance = tickDistance * scale;
    } else {
      scaledTickDistance = tickDistance * scale;
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
    /// The number of ticks to draw.
    int numTicks = (height / scaledTickDistance).ceil() + 2;
    if (scaledTickDistance > TextTickDistance) {
      textTickDistance = tickDistance;
    }
    /// Figure out the position of the top left corner of the screen
    double tickOffset = 0.0;
    double startingTickMarkValue = 0.0;
    double y = ((translation - bottom) / scale);
    startingTickMarkValue = y - (y % tickDistance);
    tickOffset = -(y % tickDistance) * scale - scaledTickDistance;

    /// Move back by one tick.
    tickOffset -= scaledTickDistance;
    startingTickMarkValue -= tickDistance;
    /// Ticks can change color because the timeline background will also change color
    /// depending on the current era. The [TickColors] object, in `timeline_utils.dart`,
    /// wraps this information.
    List<TickColors> tickColors = timeline.tickColors;
    if (tickColors.isNotEmpty) {
      /// Build up the color stops for the linear gradient.
      double rangeStart = (tickColors.first.start ?? 0.0);
      double rangeEnd = (tickColors.last.start ?? 0.0);
      double range = rangeEnd - rangeStart;
      if (range == 0) range = 1.0;
      List<ui.Color> colors = <ui.Color>[];
      List<double> stops = <double>[];
      for (TickColors bg in tickColors) {
        colors.add(bg.background ?? Colors.transparent);
        stops.add(((bg.start ?? 0.0) - rangeStart) / range);
      }
      double s =
          timeline.computeScale(timeline.renderStart, timeline.renderEnd);
      /// y-coordinate for the starting and ending element.
      double y1 = ((tickColors.first.start ?? 0.0) - timeline.renderStart) * s;
      double y2 = ((tickColors.last.start ?? 0.0) - timeline.renderStart) * s;

      /// Fill Background.
      ui.Paint paint = ui.Paint()
        ..shader = ui.Gradient.linear(
            ui.Offset(0.0, y1), ui.Offset(0.0, y2), colors, stops)
        ..style = ui.PaintingStyle.fill;

      /// Fill in top/bottom if necessary.
      if (y1 > offset.dy) {
        canvas.drawRect(
            Rect.fromLTWH(
                offset.dx, offset.dy, gutterWidth, y1 - offset.dy + 1.0),
            ui.Paint()..color = (tickColors.first.background ?? Colors.transparent));
      }
      if (y2 < offset.dy + height) {
        canvas.drawRect(
            Rect.fromLTWH(
                offset.dx, y2 - 1, gutterWidth, (offset.dy + height) - y2),
            ui.Paint()..color = (tickColors.last.background ?? Colors.transparent));
      }
      /// Draw the gutter.
      canvas.drawRect(
          Rect.fromLTWH(offset.dx, y1, gutterWidth, y2 - y1), paint);

    } else {
      canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, gutterWidth, height),
          Paint()..color = Color.fromRGBO(246, 246, 246, 0.95));
    }

    Set<String> usedValues = Set<String>();

    /// Draw all the ticks.
    for (int i = 0; i < numTicks; i++) {
      tickOffset += scaledTickDistance;

      int tt = startingTickMarkValue.round();
      // tt = -tt; // 原本是显示“多少年前”，所以取负。
      int o = tickOffset.floor();
      TickColors? colors = timeline.findTickColors(offset.dy + height - o);
      if (colors == null) {
        startingTickMarkValue += tickDistance;
        continue;
      }
      if (tt % textTickDistance == 0) {
        /// Every `textTickDistance`, draw a wider tick with the a label laid on top.
        canvas.drawRect(
            Rect.fromLTWH(offset.dx + gutterWidth - TickSize,
                offset.dy + height - o, TickSize, 1.0),
            Paint()..color = (colors.long ?? Colors.transparent));
        /// Drawing text to [canvas] is done by using the [ParagraphBuilder] directly.
        ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
            textAlign: TextAlign.end, fontFamily: "Roboto", fontSize: 10.0))
          ..pushStyle(ui.TextStyle(
              color: colors.text ?? Colors.transparent));

        int value = tt.round();
        String label;
        if (timeline.isCalendarMode) {
          label = _formatCalendarLabel(value.toDouble(), textTickDistance.toInt());
        } else if (timeline.isDistanceMode) {
          if (value < 0) {
            startingTickMarkValue += tickDistance;
            continue;
          }
          label = "$value km";
        } else {
          label = TimelineEntry.formatYears(value.toDouble());
        }
        
        usedValues.add(label);
        builder.addText(label);
        ui.Paragraph tickParagraph = builder.build();
        tickParagraph.layout(ui.ParagraphConstraints(
            width: gutterWidth - LabelPadLeft - LabelPadRight));
        canvas.drawParagraph(
            tickParagraph,
            Offset(offset.dx + LabelPadLeft - LabelPadRight,
                offset.dy + height - o - tickParagraph.height - 5));
      } else {
        /// If we're within two text-ticks, just draw a smaller line.
        canvas.drawRect(
            Rect.fromLTWH(offset.dx + gutterWidth - SmallTickSize,
                offset.dy + height - o, SmallTickSize, 1.0),
            Paint()..color = (colors.short ?? Colors.transparent));
      }
      startingTickMarkValue += tickDistance;
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
