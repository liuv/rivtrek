import 'package:flare_dart/actor_skin.dart';

import "actor_artboard.dart";
import "actor_component.dart";
import "actor_node.dart";
import "math/mat2d.dart";
import "stream_reader.dart";

class SkinnedBone {
  int boneIdx = 0;
  late ActorNode node;
  Mat2D bind = Mat2D();
  Mat2D inverseBind = Mat2D();
}

mixin ActorSkinnable {
  ActorSkin? skin;
  List<SkinnedBone> _connectedBones = <SkinnedBone>[];
  set worldTransformOverride(Mat2D? value);

  List<SkinnedBone> get connectedBones => _connectedBones;
  bool get isConnectedToBones =>
      _connectedBones.isNotEmpty;

  static ActorSkinnable read(
      ActorArtboard artboard, StreamReader reader, ActorSkinnable node) {
    reader.openArray("bones");
    int numConnectedBones = reader.readUint8Length();
    if (numConnectedBones != 0) {
      node._connectedBones = List<SkinnedBone>.generate(numConnectedBones, (i) => SkinnedBone());

      for (int i = 0; i < numConnectedBones; i++) {
        SkinnedBone bc = node._connectedBones[i];
        reader.openObject("bone");
        bc.boneIdx = reader.readId("component");
        Mat2D.copyFromList(bc.bind, reader.readFloat32Array(6, "bind"));
        reader.closeObject();
        Mat2D.invert(bc.inverseBind, bc.bind);
      }
      reader.closeArray();
      Mat2D worldOverride = Mat2D();
      Mat2D.copyFromList(worldOverride, reader.readFloat32Array(6, "worldTransform"));
      node.worldTransformOverride = worldOverride;
    } else {
      reader.closeArray();
    }

    return node;
  }

  void resolveSkinnable(List<ActorComponent?> components) {
    for (int i = 0; i < _connectedBones.length; i++) {
      SkinnedBone bc = _connectedBones[i];
      bc.node = components[bc.boneIdx] as ActorNode;
    }
  }

  void copySkinnable(ActorSkinnable node, ActorArtboard resetArtboard) {
    _connectedBones = List<SkinnedBone>.generate(node._connectedBones.length, (i) {
      SkinnedBone from = node._connectedBones[i];
      SkinnedBone bc = SkinnedBone();
      bc.boneIdx = from.boneIdx;
      Mat2D.copy(bc.bind, from.bind);
      Mat2D.copy(bc.inverseBind, from.inverseBind);
      return bc;
    });
  }

  void invalidateDrawable();
}
