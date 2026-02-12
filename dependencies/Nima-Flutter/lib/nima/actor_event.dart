import "actor.dart";
import "actor_component.dart";
import "readers/stream_reader.dart";

class ActorEvent extends ActorComponent {
  static ActorComponent read(
      Actor actor, StreamReader reader, ActorEvent? component) {
    component ??= ActorEvent();

    ActorComponent.read(actor, reader, component);

    return component;
  }

  @override
  ActorComponent makeInstance(Actor resetActor) {
    ActorEvent instanceEvent = ActorEvent();
    instanceEvent.copyComponent(this, resetActor);
    return instanceEvent;
  }

  @override
  void completeResolve() {}
  @override
  void onDirty(int dirt) {}
  @override
  void update(int dirt) {}
}
