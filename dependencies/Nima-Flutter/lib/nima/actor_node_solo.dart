import "dart:math";

import "actor.dart";
import "actor_component.dart";
import "actor_node.dart";
import "readers/stream_reader.dart";

class ActorNodeSolo extends ActorNode {
  int _activeChildIndex = 0;

  set activeChildIndex(int idx) {
    if (idx != _activeChildIndex) {
      setActiveChildIndex(idx);
    }
  }

  int get activeChildIndex {
    return _activeChildIndex;
  }

  void setActiveChildIndex(int idx) {
    _activeChildIndex = min(children.length, max(0, idx));
    for (int i = 0; i < children.length; i++) {
      var child = children[i];
      bool cv = (i != (_activeChildIndex - 1));
      child.collapsedVisibility = cv; // Setter
    }
    }

  @override
  ActorComponent makeInstance(Actor resetActor) {
    ActorNodeSolo soloInstance = ActorNodeSolo();
    soloInstance.copySolo(this, resetActor);
    return soloInstance;
  }

  void copySolo(ActorNodeSolo node, Actor resetActor) {
    copyNode(node, resetActor);
    _activeChildIndex = node._activeChildIndex;
  }

  static ActorNodeSolo read(
      Actor actor, StreamReader reader, ActorNodeSolo? node) {
    node ??= ActorNodeSolo();

    ActorNode.read(actor, reader, node);
    node._activeChildIndex = reader.readUint32("activeChild");
    return node;
  }

  @override
  void completeResolve() {
    super.completeResolve();
    setActiveChildIndex(activeChildIndex);
  }
}
