import "actor.dart";
import "actor_node.dart";
import "math/mat2d.dart";
import "math/vec2d.dart";
import "readers/stream_reader.dart";

class ActorBoneBase extends ActorNode {
  double _length = 0.0;
  bool isConnectedToImage = false;

  double get length {
    return _length;
  }

  set length(double value) {
    if (_length == value) {
      return;
    }
    _length = value;
    for (final ActorNode node in children) {
      if (node is ActorBoneBase) {
        node.x = value;
      }
    }
  }

  Vec2D getTipWorldTranslation(Vec2D vec) {
    Mat2D transform = Mat2D();
    transform[4] = _length;
    Mat2D.multiply(transform, worldTransform, transform);
    vec[0] = transform[4];
    vec[1] = transform[5];
    return vec;
  }

  static ActorBoneBase read(
      Actor actor, StreamReader reader, ActorBoneBase? node) {
    node ??= ActorBoneBase();
    ActorNode.read(actor, reader, node);

    node._length = reader.readFloat32("length");

    return node;
  }

  void copyBoneBase(ActorBoneBase node, Actor resetActor) {
    super.copyNode(node, resetActor);
    _length = node._length;
    isConnectedToImage = node.isConnectedToImage;
  }
}
