import "actor.dart";
import "actor_bone.dart";
import "actor_component.dart";
import "actor_node.dart";
import "readers/stream_reader.dart";

class ActorRootBone extends ActorNode {
  ActorBone? _firstBone;

  ActorBone? get firstBone {
    return _firstBone;
  }

  @override
  void completeResolve() {
    super.completeResolve();
    for (final ActorNode node in children) {
      if (node is ActorBone) {
        _firstBone = node;
        return;
      }
    }
  }

  @override
  ActorComponent makeInstance(Actor resetActor) {
    ActorRootBone instanceNode = ActorRootBone();
    instanceNode.copyNode(this, resetActor);
    return instanceNode;
  }

  static ActorRootBone read(
      Actor actor, StreamReader reader, ActorRootBone? node) {
    node ??= ActorRootBone();
    ActorNode.read(actor, reader, node);
    return node;
  }
}
