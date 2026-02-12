import "actor.dart";
import "actor_component.dart";
import "actor_constraint.dart";
import "actor_node.dart";
import "readers/stream_reader.dart";

abstract class ActorTargetedConstraint extends ActorConstraint {
  int _targetIdx = 0;
  ActorComponent? _target;

  ActorComponent? get target {
    return _target;
  }

  @override
  void resolveComponentIndices(List<ActorComponent> components) {
    super.resolveComponentIndices(components);
    if (_targetIdx != 0) {
      _target = components[_targetIdx];
      ActorNode? p = parent;
      ActorComponent? t = _target;
      if (p != null && t != null) {
        actor.addDependency(p, t);
      }
    }
  }

  static void read(
      Actor actor, StreamReader reader, ActorTargetedConstraint component) {
    ActorConstraint.read(actor, reader, component);
    component._targetIdx = reader.readId("targetId");
  }

  void copyTargetedConstraint(ActorTargetedConstraint node, Actor resetActor) {
    copyConstraint(node, resetActor);

    _targetIdx = node._targetIdx;
  }
}
