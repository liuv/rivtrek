import 'package:flare_dart/actor_artboard.dart';
import 'package:flare_dart/actor_shape.dart';
import 'package:flare_dart/stream_reader.dart';

import "actor_node.dart";
import "math/aabb.dart";

enum BlendModes { Normal, Multiply, Screen, Additive }

abstract class ActorDrawable extends ActorNode {
  late List<List<ActorShape>> _clipShapes;
  List<List<ActorShape>> get clipShapes => _clipShapes;

  // Editor set draw index.
  late int _drawOrder;
  int get drawOrder => _drawOrder;
  set drawOrder(int value) {
    if (_drawOrder == value) {
      return;
    }
    _drawOrder = value;
    artboard.markDrawOrderDirty();
  }

  // Computed draw index in the draw list.
  late int drawIndex;
  late bool isHidden;

  bool get doesDraw {
    return !isHidden && !renderCollapsed;
  }

  int get blendModeId;
  set blendModeId(int value);

  static ActorDrawable read(
      ActorArtboard artboard, StreamReader reader, ActorDrawable component) {
    ActorNode.read(artboard, reader, component);

    component.isHidden = !reader.readBool("isVisible");
    component.blendModeId = artboard.actor.version < 21 ? 3 : reader.readUint8("blendMode");
    component.drawOrder = reader.readUint16("drawOrder");

    return component;
  }

  void copyDrawable(ActorDrawable node, ActorArtboard resetArtboard) {
    copyNode(node, resetArtboard);
    // todo blendmode
    drawOrder = node.drawOrder;
    blendModeId = node.blendModeId;
    isHidden = node.isHidden;
  }

  AABB computeAABB();
  void initializeGraphics() {}

  @override
  void completeResolve() {
    _clipShapes = [];
    List<List<ActorClip>> clippers = allClips;
    for (final List<ActorClip> clips in clippers) {
      List<ActorShape> shapes = [];
      for (final ActorClip clip in clips) {
        clip.node?.all((ActorNode node) {
          if (node is ActorShape) {
            shapes.add(node);
          }
          return true;
        });
      }
      if (shapes.isNotEmpty) {
        _clipShapes.add(shapes);
      }
    }
  }
}
