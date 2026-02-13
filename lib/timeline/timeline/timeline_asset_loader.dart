import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flare_flutter/flare.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:flutter/services.dart' show rootBundle;
import 'package:nima/nima.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:rive/rive.dart' as rive;
import 'package:rivtrek/timeline/timeline/timeline_entry.dart';
import 'package:rivtrek/timeline/timeline/timeline_utils.dart';

class LoadedTimelineAsset {
  LoadedTimelineAsset({required this.asset, required this.filename});

  final TimelineAsset asset;
  final String filename;
}

class TimelineAssetLoader {
  TimelineAssetLoader({
    required Map<String, nima.FlutterActor> nimaResources,
    required Map<String, flare.FlutterActor> flareResources,
    required Map<String, dynamic> riveResources,
  })  : _nimaResources = nimaResources,
        _flareResources = flareResources,
        _riveResources = riveResources;

  final Map<String, nima.FlutterActor> _nimaResources;
  final Map<String, flare.FlutterActor> _flareResources;
  final Map<String, dynamic> _riveResources;

  Future<LoadedTimelineAsset?> loadFromAssetMap(Map assetMap) async {
    final dynamic sourceAttr = assetMap["source"];
    if (sourceAttr == null || sourceAttr == "") {
      return null;
    }
    final String source = sourceAttr as String;
    final String filename = "assets/timeline/$source";
    final String extension = getExtension(source);

    TimelineAsset? asset;
    switch (extension) {
      case "flr":
        asset = await _loadFlareAsset(filename, assetMap);
        break;
      case "nma":
        asset = await _loadNimaAsset(filename, assetMap);
        break;
      case "riv":
        asset = await loadRiveAssetFromMap(filename, assetMap);
        break;
      default:
        asset = await _loadImageAsset(filename);
        break;
    }
    if (asset == null) {
      return null;
    }
    _applyLayout(asset, assetMap);
    return LoadedTimelineAsset(asset: asset, filename: filename);
  }

  Future<TimelineFlare?> _loadFlareAsset(String filename, Map assetMap) async {
    final TimelineFlare flareAsset = TimelineFlare();
    flare.FlutterActor? actor = _flareResources[filename];
    if (actor == null) {
      actor = flare.FlutterActor();
      final bool success = await actor.loadFromBundle(rootBundle, filename);
      if (success) {
        _flareResources[filename] = actor;
      }
    }
    if (actor.artboard == null) {
      return null;
    }

    flareAsset.actorStatic = actor.artboard as flare.FlutterActorArtboard;
    flareAsset.actorStatic?.initializeGraphics();
    flareAsset.actor =
        actor.artboard!.makeInstance() as flare.FlutterActorArtboard;
    flareAsset.actor?.initializeGraphics();

    if (actor.artboard!.animations.isNotEmpty) {
      flareAsset.animation = actor.artboard!.animations[0];
    }

    dynamic name = assetMap["idle"] ?? assetMap["animations"];
    if (name is String) {
      if ((flareAsset.idle = flareAsset.actor?.getAnimation(name)) != null) {
        flareAsset.animation = flareAsset.idle;
      }
    } else if (name is List) {
      for (final String animationName in name) {
        final flare.ActorAnimation? animation =
            flareAsset.actor?.getAnimation(animationName);
        if (animation != null) {
          flareAsset.idleAnimations ??= <flare.ActorAnimation>[];
          flareAsset.idleAnimations?.add(animation);
          flareAsset.animation = animation;
        }
      }
    }

    name = assetMap["intro"];
    if (name is String) {
      if ((flareAsset.intro = flareAsset.actor?.getAnimation(name)) != null) {
        flareAsset.animation = flareAsset.intro;
      }
    }

    flareAsset.animationTime = 0.0;
    flareAsset.actor?.advance(0.0);
    flareAsset.setupAABB = flareAsset.actor?.computeAABB();
    if (flareAsset.setupAABB == null ||
        (flareAsset.setupAABB![0] == 0 && flareAsset.setupAABB![2] == 0)) {
      flareAsset.setupAABB = flare.AABB.fromValues(
          -flareAsset.width / 2,
          -flareAsset.height / 2,
          flareAsset.width / 2,
          flareAsset.height / 2);
    }
    if (flareAsset.animation != null) {
      flareAsset.animation!
          .apply(flareAsset.animationTime, flareAsset.actor!, 1.0);
      flareAsset.animation!
          .apply(flareAsset.animation!.duration, flareAsset.actorStatic!, 1.0);
    }
    flareAsset.actor?.advance(0.0);
    flareAsset.actorStatic?.advance(0.0);

    final dynamic loop = assetMap["loop"];
    flareAsset.loop = loop is bool ? loop : true;
    flareAsset.offset = _toDouble(assetMap["offset"], 0.0);
    flareAsset.gap = _toDouble(assetMap["gap"], 0.0);

    final dynamic bounds = assetMap["bounds"];
    if (bounds is List) {
      flareAsset.setupAABB = flare.AABB.fromValues(
          _toDouble(bounds[0], 0.0),
          _toDouble(bounds[1], 0.0),
          _toDouble(bounds[2], 0.0),
          _toDouble(bounds[3], 0.0));
    }
    return flareAsset;
  }

  Future<TimelineNima?> _loadNimaAsset(String filename, Map assetMap) async {
    final TimelineNima nimaAsset = TimelineNima();
    nima.FlutterActor? actor = _nimaResources[filename];
    if (actor == null) {
      actor = nima.FlutterActor();
      final bool success = await actor.loadFromBundle(filename);
      if (success) {
        _nimaResources[filename] = actor;
      }
    }
    nimaAsset.actorStatic = actor;
    nimaAsset.actor = actor.makeInstance() as nima.FlutterActor;

    final dynamic name = assetMap["idle"];
    if (name is String) {
      nimaAsset.animation = nimaAsset.actor?.getAnimation(name);
    } else if (actor.animations.isNotEmpty) {
      nimaAsset.animation = actor.animations[0];
    }
    nimaAsset.animationTime = 0.0;
    nimaAsset.actor?.advance(0.0);

    nimaAsset.setupAABB = nimaAsset.actor?.computeAABB();
    if (nimaAsset.setupAABB == null ||
        (nimaAsset.setupAABB![0] == 0 && nimaAsset.setupAABB![2] == 0)) {
      nimaAsset.setupAABB = nima.AABB.fromValues(-nimaAsset.width / 2,
          -nimaAsset.height / 2, nimaAsset.width / 2, nimaAsset.height / 2);
    }
    if (nimaAsset.animation != null) {
      nimaAsset.animation!.apply(nimaAsset.animationTime, nimaAsset.actor!, 1.0);
      nimaAsset.animation!
          .apply(nimaAsset.animation!.duration, nimaAsset.actorStatic!, 1.0);
    }
    nimaAsset.actor?.advance(0.0);
    nimaAsset.actorStatic?.advance(0.0);

    final dynamic loop = assetMap["loop"];
    nimaAsset.loop = loop is bool ? loop : true;
    nimaAsset.offset = _toDouble(assetMap["offset"], 0.0);
    nimaAsset.gap = _toDouble(assetMap["gap"], 0.0);

    final dynamic bounds = assetMap["bounds"];
    if (bounds is List) {
      nimaAsset.setupAABB = nima.AABB.fromValues(
          _toDouble(bounds[0], 0.0),
          _toDouble(bounds[1], 0.0),
          _toDouble(bounds[2], 0.0),
          _toDouble(bounds[3], 0.0));
    }
    return nimaAsset;
  }

  Future<TimelineImage> _loadImageAsset(String filename) async {
    final TimelineImage imageAsset = TimelineImage();
    final ByteData data = await rootBundle.load(filename);
    final Uint8List list = Uint8List.view(data.buffer);
    final ui.Codec codec = await ui.instantiateImageCodec(list);
    final ui.FrameInfo frame = await codec.getNextFrame();
    imageAsset.image = frame.image;
    return imageAsset;
  }

  Future<TimelineRive?> loadRiveAssetFromMap(String filename, Map assetMap) async {
    final TimelineRive riveAsset = TimelineRive();
    dynamic actor = _riveResources[filename];
    if (actor == null) {
      try {
        final ByteData data = await rootBundle.load(filename);
        final rive.RiveFile file = rive.RiveFile.import(data);
        actor = file.mainArtboard;
        _riveResources[filename] = actor;
      } catch (_) {
        return null;
      }
    }
    if (actor == null) {
      return null;
    }
    riveAsset.actorStatic = actor;
    riveAsset.actor = actor.instance();
    if (riveAsset.actor.animations.isNotEmpty) {
      riveAsset.animation = riveAsset.actor.animations[0];
    }

    dynamic name = assetMap["idle"];
    if (name is String) {
      try {
        final dynamic anim = (riveAsset.actor.animations as Iterable)
            .firstWhere((a) => a.name == name, orElse: () => null);
        if (anim != null) {
          riveAsset.idle = anim;
          riveAsset.animation = anim;
        }
      } catch (_) {}
    } else if (name is List) {
      for (final String animationName in name) {
        try {
          final dynamic anim = (riveAsset.actor.animations as Iterable)
              .firstWhere((a) => a.name == animationName, orElse: () => null);
          if (anim != null) {
            riveAsset.idleAnimations ??= <dynamic>[];
            riveAsset.idleAnimations?.add(anim);
            riveAsset.animation = anim;
          }
        } catch (_) {}
      }
    }

    final dynamic animationsNode = assetMap["animations"];
    if (animationsNode is List) {
      for (final dynamic animationName in animationsNode) {
        if (animationName is! String) {
          continue;
        }
        try {
          final dynamic anim = (riveAsset.actor.animations as Iterable)
              .firstWhere((a) => a.name == animationName, orElse: () => null);
          if (anim != null) {
            riveAsset.idleAnimations ??= <dynamic>[];
            if (!riveAsset.idleAnimations!.contains(anim)) {
              riveAsset.idleAnimations!.add(anim);
            }
            riveAsset.animation = anim;
          }
        } catch (_) {}
      }
    }
    if ((riveAsset.idleAnimations == null || riveAsset.idleAnimations!.isEmpty) &&
        riveAsset.actor.animations is Iterable &&
        (riveAsset.actor.animations as Iterable).length > 1) {
      riveAsset.idleAnimations = <dynamic>[];
      for (final dynamic anim in (riveAsset.actor.animations as Iterable)) {
        if (anim is rive.LinearAnimation) {
          riveAsset.idleAnimations!.add(anim);
        }
      }
    }

    name = assetMap["intro"];
    if (name is String) {
      try {
        final dynamic anim = (riveAsset.actor.animations as Iterable)
            .firstWhere((a) => a.name == name, orElse: () => null);
        if (anim != null) {
          riveAsset.intro = anim;
          riveAsset.animation = anim;
          if (riveAsset.idleAnimations != null) {
            riveAsset.idleAnimations!.remove(anim);
          }
        }
      } catch (_) {}
    }

    riveAsset.animationTime = 0.0;
    riveAsset.actor.advance(0.0);
    if (riveAsset.animation != null) {
      riveAsset.animation.apply(0.0, coreContext: riveAsset.actor, mix: 1.0);
    }
    riveAsset.actor.advance(0.0);
    riveAsset.actorStatic.advance(0.0);

    final dynamic loop = assetMap["loop"];
    riveAsset.loop = loop is bool ? loop : true;
    riveAsset.offset = _toDouble(assetMap["offset"], 0.0);
    riveAsset.gap = _toDouble(assetMap["gap"], 0.0);

    final double scale = _toDouble(assetMap["scale"], 1.0);
    final dynamic width = assetMap["width"];
    final dynamic height = assetMap["height"];
    riveAsset.width = width is num ? width.toDouble() * scale : 300.0 * scale;
    riveAsset.height =
        height is num ? height.toDouble() * scale : 300.0 * scale;

    final dynamic bounds = assetMap["bounds"];
    if (bounds is List && bounds.length >= 4) {
      riveAsset.setupAABB = [
        _toDouble(bounds[0], 0.0),
        _toDouble(bounds[1], 0.0),
        _toDouble(bounds[2], 0.0),
        _toDouble(bounds[3], 0.0),
      ];
    } else {
      riveAsset.setupAABB = [0.0, 0.0, riveAsset.width, riveAsset.height];
    }
    return riveAsset;
  }

  void _applyLayout(TimelineAsset asset, Map assetMap) {
    final double scale = _toDouble(assetMap["scale"], 1.0);
    final double width = _toDouble(assetMap["width"], 0.0);
    final double height = _toDouble(assetMap["height"], 0.0);
    asset.width = width * scale;
    asset.height = height * scale;
  }

  double _toDouble(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }
}
