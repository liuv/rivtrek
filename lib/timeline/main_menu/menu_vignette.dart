import 'dart:math';
import 'dart:ui' as ui;

import 'package:flare_flutter/flare.dart' as flare;
import 'package:flare_dart/animation/actor_animation.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:nima/nima.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:rive/rive.dart' as rive;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:rivtrek/timeline/bloc_provider.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline/timeline_entry.dart';

/// This is a [LeafRenderObjectWidget]. It's used to render the [FlutterActor]s
/// that are the background of each [MenuSection] in the [MainMenu].
class MenuVignette extends LeafRenderObjectWidget {
  final Color? gradientColor;
  final bool isActive;
  final String assetId;

  const MenuVignette(
      {Key? key,
      required this.gradientColor,
      required this.isActive,
      required this.assetId})
      : super(key: key);

  @override
  MenuVignetteRenderObject createRenderObject(BuildContext context) {
    Timeline t = BlocProvider.getTimeline(context);
    return MenuVignetteRenderObject()
      ..timeline = t
      ..assetId = assetId
      ..gradientColor = gradientColor
      ..isActive = isActive;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant MenuVignetteRenderObject renderObject) {
    Timeline t = BlocProvider.getTimeline(context);
    renderObject
      ..timeline = t
      ..assetId = assetId
      ..gradientColor = gradientColor
      ..isActive = isActive;
  }

  @override
  didUnmountRenderObject(covariant MenuVignetteRenderObject renderObject) {
    renderObject.isActive = false;
  }
}

/// When extending a [RenderBox] we provide a custom set of instructions for the widget being rendered.
///
/// In particular this means overriding the [paint()] and [hitTestSelf()] methods to render the loaded
/// Flare/Nima [FlutterActor] where the widget is being placed.
class MenuVignetteRenderObject extends RenderBox {
  /// The [_timeline] object is used here to retrieve the asset through [getById()].
  Timeline? _timeline;
  String _assetId = '';

  /// If this object is not active, stop playing. This optimizes resource consumption
  /// and makes sure that each [FlutterActor] remains coherent throughout its animation.
  bool _isActive = false;
  bool _firstUpdate = true;
  double _lastFrameTime = 0.0;
  Color? gradientColor;
  bool _isFrameScheduled = false;
  double opacity = 0.0;

  Timeline get timeline => _timeline!;
  set timeline(Timeline value) {
    if (_timeline == value) {
      return;
    }
    _timeline = value;
    _firstUpdate = true;
    updateRendering();
  }

  set assetId(String id) {
    if (_assetId != id) {
      _assetId = id;
      updateRendering();
    }
  }

  bool get isActive => _isActive;
  set isActive(bool value) {
    if (_isActive == value) {
      return;
    }

    /// When this [RenderBox] becomes active, start advancing it again.
    _isActive = value;
    updateRendering();
  }

  TimelineEntry? get timelineEntry {
    if (_timeline == null) {
      return TimelineEntry();
    }
    return _timeline!.getById(_assetId);
  }

  @override
  bool get sizedByParent => true;

  @override
  bool hitTestSelf(Offset screenOffset) => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  /// Uses the [SchedulerBinding] to trigger a new paint for this widget.
  void updateRendering() {
    if (_isActive) {
      markNeedsPaint();
      if (!_isFrameScheduled) {
        _isFrameScheduled = true;
        SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
      }
    }
    markNeedsLayout();
  }

  /// This overridden method is where we can implement our custom drawing logic, for
  /// laying out the [FlutterActor], and drawing it to [canvas].
  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    TimelineEntry? entry = timelineEntry;
    TimelineAsset? asset = entry?.asset;

    /// Don't paint if not needed.
    if (asset == null) {
      opacity = 0.0;
      return;
    }

    if (asset is TimelineImage) {
      canvas.drawImageRect(
          asset.image!,
          Rect.fromLTWH(0.0, 0.0, asset.width, asset.height),
          offset & size,
          Paint()
            ..isAntiAlias = true
            ..filterQuality = ui.FilterQuality.low
            ..color = Colors.white.withOpacity(asset.opacity));
    } else {
      dynamic bounds;
      Alignment alignment = Alignment.center;
      BoxFit fit = BoxFit.cover;
      bool isNima = false;
      bool isFlare = false;

      if (asset is TimelineNima && asset.actor != null) {
        bounds = asset.setupAABB ?? nima.AABB.fromValues(0, 0, 0, 0);
        alignment = Alignment.topRight;
        isNima = true;
      } else if (asset is TimelineFlare && asset.actor != null) {
        bounds = asset.setupAABB ?? flare.AABB.fromValues(0, 0, 0, 0);
        isFlare = true;
      } else if (asset is TimelineRive && asset.actor != null) {
        bounds = asset.setupAABB ??
            [0.0, 0.0, asset.actor!.width, asset.actor!.height];
      }

      if (bounds == null) return;

      // 容错处理
      if (bounds[0] == 0 &&
          bounds[1] == 0 &&
          bounds[2] == 0 &&
          bounds[3] == 0) {
        bounds = [
          -asset.width / 2,
          -asset.height / 2,
          asset.width / 2,
          asset.height / 2
        ];
      }

      double contentWidth = (bounds[2] - bounds[0]).toDouble();
      double contentHeight = (bounds[3] - bounds[1]).toDouble();
      if (contentWidth == 0) contentWidth = 1.0;
      if (contentHeight == 0) contentHeight = 1.0;

      double x =
          -bounds[0] - contentWidth / 2.0 - (alignment.x * contentWidth / 2.0);
      double y = -bounds[1] -
          contentHeight / 2.0 +
          (alignment.y * contentHeight / 2.0);

      Offset renderOffset = offset;
      Size renderSize = size;
      double scaleX = 1.0, scaleY = 1.0;

      switch (fit) {
        case BoxFit.fill:
          scaleX = renderSize.width / contentWidth;
          scaleY = renderSize.height / contentHeight;
          break;
        case BoxFit.contain:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale;
          break;
        case BoxFit.cover:
          double maxScale = max(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = maxScale;
          break;
        case BoxFit.fitHeight:
          scaleX = scaleY = renderSize.height / contentHeight;
          break;
        case BoxFit.fitWidth:
          scaleX = scaleY = renderSize.width / contentWidth;
          break;
        case BoxFit.none:
          scaleX = scaleY = 1.0;
          break;
        case BoxFit.scaleDown:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
          break;
      }

      canvas.save();
      canvas.translate(
          renderOffset.dx +
              renderSize.width / 2.0 +
              (alignment.x * renderSize.width / 2.0),
          renderOffset.dy +
              renderSize.height / 2.0 +
              (alignment.y * renderSize.height / 2.0));

      canvas.scale(scaleX, isNima ? -scaleY : scaleY);
      canvas.translate(x, y);

      if (isFlare) {
        (asset as TimelineFlare).actor?.modulateOpacity = 1.0;
        asset.actor?.draw(canvas);
      } else if (isNima) {
        (asset as TimelineNima).actor?.draw(canvas, 1.0);
      } else if (asset is TimelineRive) {
        asset.actor?.draw(canvas);
      }

      canvas.restore();

      // 绘制渐变层
      double gradientFade = 1.0 - opacity;
      List<ui.Color> colors = <ui.Color>[
        gradientColor!.withOpacity(gradientFade),
        gradientColor!.withOpacity(min(1.0, gradientFade + 0.9))
      ];
      List<double> stops = <double>[0.0, 1.0];

      ui.Paint paint = ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset(0.0, offset.dy),
            ui.Offset(0.0, offset.dy + 150.0), colors, stops)
        ..style = ui.PaintingStyle.fill;
      canvas.drawRect(offset & size, paint);
    }
  }

  /// This callback is used by the [SchedulerBinding] in order to advance the Flare/Nima
  /// animations properly, and update the corresponding [FlutterActor]s.
  void beginFrame(Duration timeStamp) {
    _isFrameScheduled = false;
    final double t =
        timeStamp.inMicroseconds / Duration.microsecondsPerMillisecond / 1000.0;
    if (_lastFrameTime == 0) {
      _isFrameScheduled = true;
      _lastFrameTime = t;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
      return;
    }

    double elapsed = t - _lastFrameTime;
    _lastFrameTime = t;
    TimelineEntry? entry = timelineEntry;
    if (entry != null) {
      TimelineAsset? asset = entry.asset;
      if (asset != null) {
        // 更新透明度
        if (opacity < 1.0) {
          opacity = min(opacity + elapsed, 1.0);
        }
        if (asset is TimelineAnimatedAsset) {
          asset.animationTime += elapsed;
        }

        if (asset is TimelineNima && asset.actor != null) {
          if (asset.loop && asset.animation != null) {
            asset.animationTime %= asset.animation!.duration;
          }
          asset.animation?.apply(asset.animationTime, asset.actor!, 1.0);
          asset.actor!.advance(elapsed);
        } else if (asset is TimelineFlare && asset.actor != null) {
          if (_firstUpdate) {
            if (asset.intro != null) {
              asset.animation = asset.intro;
              asset.animationTime = -0.01;
            }
            _firstUpdate = false;
          }

          if (asset.idleAnimations != null && asset.idleAnimations!.isNotEmpty) {
            for (flare.ActorAnimation anim in asset.idleAnimations!) {
              anim.apply(asset.animationTime % anim.duration, asset.actor!, 1.0);
            }
          } else {
            if (asset.intro == asset.animation &&
                asset.animation != null &&
                asset.animationTime >= asset.animation!.duration) {
              asset.animationTime -= asset.animation!.duration;
              asset.animation = asset.idle;
            }
            if (asset.loop && asset.animationTime >= 0 && asset.animation != null) {
              asset.animationTime %= asset.animation!.duration;
            }
            asset.animation?.apply(asset.animationTime, asset.actor!, 1.0);
          }
          // 这里的 advance 必须确保参数正确
          asset.actor!.advance(elapsed > 0.1 ? 0.016 : elapsed); 
        } else if (asset is TimelineRive && asset.actor != null) {
          if (_firstUpdate) {
            if (asset.intro != null) {
              asset.animation = asset.intro;
              asset.animationTime = -0.01;
            }
            _firstUpdate = false;
          }
          if (asset.idleAnimations != null && asset.idleAnimations!.isNotEmpty) {
            double phase = 0.0;
            for (final dynamic animation in asset.idleAnimations!) {
              if (animation is rive.LinearAnimation) {
                final double duration =
                    (animation.duration as num).toDouble() /
                        (animation.fps as num).toDouble();
                final double time = duration > 0
                    ? (asset.animationTime + phase) % duration
                    : asset.animationTime + phase;
                animation.apply(time, coreContext: asset.actor, mix: 1.0);
                phase += 0.16;
              }
            }
          } else {
            rive.LinearAnimation? anim =
                asset.animation is rive.LinearAnimation
                    ? asset.animation as rive.LinearAnimation
                    : null;
            if (asset.intro == asset.animation &&
                anim != null &&
                (anim.fps as num).toDouble() > 0) {
              final double introDuration =
                  (anim.duration as num).toDouble() /
                      (anim.fps as num).toDouble();
              if (asset.animationTime >= introDuration) {
                asset.animationTime -= introDuration;
                asset.animation = asset.idle;
                anim = asset.animation is rive.LinearAnimation
                    ? asset.animation as rive.LinearAnimation
                    : null;
              }
            }
            if (anim != null) {
              final double duration =
                  (anim.duration as num).toDouble() /
                      (anim.fps as num).toDouble();
              if (asset.loop && duration > 0) {
                asset.animationTime %= duration;
              }
              anim.apply(asset.animationTime,
                  coreContext: asset.actor, mix: 1.0);
            }
          }
          // 强制刷新所有组件的变换
          asset.actor!.advance(elapsed > 0.1 ? 0.016 : elapsed);
        }
      }
    }

    markNeedsPaint();
    if (isActive && !_isFrameScheduled) {
      _isFrameScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
    }
  }
}
