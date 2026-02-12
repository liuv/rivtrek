import "../readers/stream_reader.dart";
import "../actor_component.dart";
import "../actor_event.dart";
import "../actor.dart";
import "property_types.dart";
import "keyframe.dart";

typedef KeyFrame KeyFrameReader(StreamReader reader, ActorComponent component);

class PropertyAnimation {
  late int _type;
  late List<KeyFrame> _keyFrames;

  int get propertyType {
  late return _type;
  }

  List<KeyFrame> get keyFrames {
  late return _keyFrames;
  }

  static PropertyAnimation read(StreamReader reader, ActorComponent component) {
    StreamReader propertyReader = reader.readNextBlock(PropertyTypesMap);
    if (propertyReader == null) {
      return null;
    }
    PropertyAnimation propertyAnimation = PropertyAnimation();
    int type = propertyReader.blockType;
    // Wish there were a way do to this in Dart without having to create my own hash set.
    // if(!Enum.IsDefined(typeof(PropertyTypes), type))
    // {
    // 	return null;
    // }
    // else
    // {
    propertyAnimation._type = type;

    KeyFrameReader keyFrameReader;
    switch (propertyAnimation._type) {
      case PropertyTypes.PosX:
        keyFrameReader = KeyFramePosX.read;
        break;
      case PropertyTypes.PosY:
        keyFrameReader = KeyFramePosY.read;
        break;
      case PropertyTypes.ScaleX:
        keyFrameReader = KeyFrameScaleX.read;
        break;
      case PropertyTypes.ScaleY:
        keyFrameReader = KeyFrameScaleY.read;
        break;
      case PropertyTypes.Rotation:
        keyFrameReader = KeyFrameRotation.read;
        break;
      case PropertyTypes.Opacity:
        keyFrameReader = KeyFrameOpacity.read;
        break;
      case PropertyTypes.DrawOrder:
        keyFrameReader = KeyFrameDrawOrder.read;
        break;
      case PropertyTypes.Length:
        keyFrameReader = KeyFrameLength.read;
        break;
      case PropertyTypes.VertexDeform:
        keyFrameReader = KeyFrameVertexDeform.read;
        break;
      case PropertyTypes.ConstraintStrength:
        keyFrameReader = KeyFrameConstraintStrength.read;
        break;
      case PropertyTypes.Trigger:
        keyFrameReader = KeyFrameTrigger.read;
        break;
      case PropertyTypes.IntProperty:
        keyFrameReader = KeyFrameIntProperty.read;
        break;
      case PropertyTypes.FloatProperty:
        keyFrameReader = KeyFrameFloatProperty.read;
        break;
      case PropertyTypes.StringProperty:
        keyFrameReader = KeyFrameStringProperty.read;
        break;
      case PropertyTypes.BooleanProperty:
        keyFrameReader = KeyFrameBooleanProperty.read;
        break;
      case PropertyTypes.CollisionEnabled:
        keyFrameReader = KeyFrameCollisionEnabledProperty.read;
        break;
      case PropertyTypes.ActiveChildIndex:
        keyFrameReader = KeyFrameActiveChild.read;
        break;
      case PropertyTypes.Sequence:
        keyFrameReader = KeyFrameSequence.read;
        break;
    }

    propertyReader.openArray("frames");
    int keyFrameCount = propertyReader.readUint16Length();
    propertyAnimation._keyFrames = List<KeyFrame>(keyFrameCount);
    KeyFrame lastKeyFrame;
    for (int i = 0; i < keyFrameCount; i++) {
      propertyReader.openObject("frame");
      KeyFrame frame = keyFrameReader(propertyReader, component);
      propertyAnimation._keyFrames[i] = frame;
      if (lastKeyFrame != null) {
        lastKeyFrame.setNext(frame);
      }
      lastKeyFrame = frame;
      propertyReader.closeObject();
    }
    propertyReader.closeArray();
    //}

    return propertyAnimation;
  }

  void apply(double time, ActorComponent component, double mix) {
    if (_keyFrames.length == 0) {
      return;
    }

    int idx = 0;
    // Binary find the keyframe index.
    {
      int mid = 0;
      double element = 0.0;
      int start = 0;
      int end = _keyFrames.length - 1;

      while (start <= end) {
        mid = ((start + end) >> 1);
        element = _keyFrames[mid].time;
        if (element < time) {
          start = mid + 1;
        } else if (element > time) {
          end = mid - 1;
        } else {
          start = mid;
          break;
        }
      }

      idx = start;
    }

    if (idx == 0) {
      _keyFrames[0].apply(component, mix);
    } else {
      if (idx < _keyFrames.length) {
        KeyFrame fromFrame = _keyFrames[idx - 1];
        KeyFrame toFrame = _keyFrames[idx];
        if (time == toFrame.time) {
          toFrame.apply(component, mix);
        } else {
          fromFrame.applyInterpolation(component, time, toFrame, mix);
        }
      } else {
        _keyFrames[idx - 1].apply(component, mix);
      }
    }
  }
}

class ComponentAnimation {
  late int _componentIndex;
  late List<PropertyAnimation> _properties;

  int get componentIndex {
  late return _componentIndex;
  }

  List<PropertyAnimation> get properties {
  late return _properties;
  }

  static ComponentAnimation read(
      StreamReader reader, List<ActorComponent> components) {
    reader.openObject("component");
    ComponentAnimation componentAnimation = ComponentAnimation();

    componentAnimation._componentIndex = reader.readId("component");
    int numProperties = reader.readUint16Length();

    componentAnimation._properties = List<PropertyAnimation>(numProperties);
    for (int i = 0; i < numProperties; i++) {
      componentAnimation._properties[i] = PropertyAnimation.read(
          reader, components[componentAnimation._componentIndex]);
    }
    reader.closeObject();

    return componentAnimation;
  }

  void apply(double time, List<ActorComponent> components, double mix) {
    for (PropertyAnimation propertyAnimation in _properties) {
      if (propertyAnimation != null) {
        propertyAnimation.apply(time, components[_componentIndex], mix);
      }
    }
  }
}

class AnimationEventArgs {
  late String _name;
  late ActorComponent _component;
  late int _propertyType;
  late double _keyFrameTime;
  late double _elapsedTime;

  AnimationEventArgs(String name, ActorComponent component, int type,
      double keyframeTime, double elapsedTime) {
    _name = name;
    _component = component;
    _propertyType = type;
    _keyFrameTime = keyframeTime;
    _elapsedTime = elapsedTime;
  }

  String get name {
  late return _name;
  }

  ActorComponent get component {
  late return _component;
  }

  int get propertyType {
  late return _propertyType;
  }

  double get keyFrameTime {
  late return _keyFrameTime;
  }

  double get elapsedTime {
  late return _elapsedTime;
  }
}

class ActorAnimation {
  late String _name;
  late int _fps;
  late double _duration;
  late bool _isLooping;
  late List<ComponentAnimation> _components;
  late List<ComponentAnimation> _triggerComponents;

  String get name {
  late return _name;
  }

  bool get isLooping {
  late return _isLooping;
  }

  double get duration {
  late return _duration;
  }

  List<ComponentAnimation> get animatedComponents {
  late return _components;
  }

  //Animation.prototype.triggerEvents = function(actorComponents, fromTime, toTime, triggered)
  /*
								name:component._Name,
								component:component,
								propertyType:property._Type,
								keyFrameTime:toTime,
								elapsed:0*/
  void triggerEvents(List<ActorComponent> components, double fromTime,
      double toTime, List<AnimationEventArgs> triggerEvents) {
    for (int i = 0; i < _triggerComponents.length; i++) {
      ComponentAnimation keyedComponent = _triggerComponents[i];
      for (PropertyAnimation property in keyedComponent.properties) {
        switch (property.propertyType) {
          case PropertyTypes.Trigger:
            List<KeyFrame> keyFrames = property.keyFrames;

            int kfl = keyFrames.length;
            if (kfl == 0) {
              continue;
            }

            int idx = 0;
            // Binary find the keyframe index.
            {
              int mid = 0;
              double element = 0.0;
              int start = 0;
              int end = kfl - 1;

              while (start <= end) {
                mid = ((start + end) >> 1);
                element = keyFrames[mid].time;
                if (element < toTime) {
                  start = mid + 1;
                } else if (element > toTime) {
                  end = mid - 1;
                } else {
                  start = mid;
                  break;
                }
              }

              idx = start;
            }

            //int idx = keyFrameLocation(toTime, keyFrames, 0, keyFrames.length-1);
            if (idx == 0) {
              if (kfl > 0 && keyFrames[0].time == toTime) {
                ActorComponent component =
                    components[keyedComponent.componentIndex];
                triggerEvents.add(AnimationEventArgs(component.name, component,
                    property.propertyType, toTime, 0.0));
              }
            } else {
              for (int k = idx - 1; k >= 0; k--) {
                KeyFrame frame = keyFrames[k];

                if (frame.time > fromTime) {
                  ActorComponent component =
                      components[keyedComponent.componentIndex];
                  triggerEvents.add(AnimationEventArgs(
                      component.name,
                      component,
                      property.propertyType,
                      frame.time,
                      toTime - frame.time));
                  /*triggered.push({
										name:component._Name,
										component:component,
										propertyType:property._Type,
										keyFrameTime:frame._Time,
										elapsed:toTime-frame._Time
									});*/
                } else {
                  break;
                }
              }
            }
            break;
          default:
            break;
        }
      }
    }
  }

  void apply(double time, Actor actor, double mix) {
    for (ComponentAnimation componentAnimation in _components) {
      componentAnimation.apply(time, actor.components, mix);
    }
  }

  static ActorAnimation read(
      StreamReader reader, List<ActorComponent> components) {
    ActorAnimation animation = ActorAnimation();
    animation._name = reader.readString("name");
    animation._fps = reader.readUint8("fos");
    animation._duration = reader.readFloat32("duration");
    animation._isLooping = reader.readBool("isLooping");

    reader.openArray("keyed");
    int numKeyedComponents = reader.readUint16Length();
    //animation._components = new ComponentAnimation[numKeyedComponents];

    // We distinguish between animated and triggered components as ActorEvents are currently only used to trigger events and don't need
    // the full animation cycle. This lets them optimize them out of the regular animation cycle.
    int animatedComponentCount = 0;
    int triggerComponentCount = 0;

    List<ComponentAnimation?> animatedComponents = List<ComponentAnimation?>.filled(numKeyedComponents, null);
    for (int i = 0; i < numKeyedComponents; i++) {
      ComponentAnimation componentAnimation =
          ComponentAnimation.read(reader, components);
      animatedComponents[i] = componentAnimation;
      if (componentAnimation != null) {
        ActorComponent actorComponent =
            components[componentAnimation.componentIndex];
        if (actorComponent != null) {
          if (actorComponent is ActorEvent) {
            triggerComponentCount++;
          } else {
            animatedComponentCount++;
          }
        }
      }
    }
    reader.closeArray();
    animation._components = List<ComponentAnimation>(animatedComponentCount);
    animation._triggerComponents =
        List<ComponentAnimation>(triggerComponentCount);

    // Put them in their respective lists.
    int animatedComponentIndex = 0;
    int triggerComponentIndex = 0;
    for (int i = 0; i < numKeyedComponents; i++) {
      ComponentAnimation componentAnimation = animatedComponents[i];
      if (componentAnimation != null) {
        ActorComponent actorComponent =
            components[componentAnimation.componentIndex];
        if (actorComponent != null) {
          if (actorComponent is ActorEvent) {
            animation._triggerComponents[triggerComponentIndex++] =
                componentAnimation;
          } else {
            animation._components[animatedComponentIndex++] =
                componentAnimation;
          }
        }
      }
    }

    return animation;
  }
}

class ActorAnimationInstance {
  late Actor _actor;
  late ActorAnimation _animation;
  late double _time;
  late double _min;
  late double _max;
  late double _range;
  late bool _loop;

  ActorAnimationInstance(Actor actor, ActorAnimation animation) {
    _actor = actor;
    _animation = animation;
    _time = 0.0;
    _min = 0.0;
    _max = animation.duration;
    _range = _max - _min;
    _loop = animation.isLooping;
  }

  double get minTime => _min;
  double get maxTime => _max;
  double get time => _time;
  bool get isOver => _time >= _max;

  void reset() {
    _time = 0.0;
    advance(0.0);
    apply(1.0);
  }

  set loop(bool shouldIt) {
    if (_loop != shouldIt) {
      _loop = shouldIt;
    }
  }

  set time(double value) {
    double delta = value - _time;
    double time = _time + (delta % _range);

    if (time < _min) {
      if (_loop) {
        time = _max - (_min - time);
      } else {
        time = _min;
      }
    } else if (time > _max) {
      if (_loop) {
        time = _min + (time - _max);
      } else {
        time = _max;
      }
    }
    _time = time;
  }

  List<AnimationEventArgs> advance(double seconds) {
    List<AnimationEventArgs> triggeredEvents = [];
    double time = _time;
    time += seconds % _range;
    if (time < _min) {
      if (_loop) {
        _animation.triggerEvents(
            _actor.components, time, _time, triggeredEvents);
        time = _max - (_min - time);
        _animation.triggerEvents(
            _actor.components, time, _max, triggeredEvents);
      } else {
        time = _min;
        if (_time != time) {
          _animation.triggerEvents(
              _actor.components, _min, _time, triggeredEvents);
        }
      }
    } else if (time > _max) {
      if (_loop) {
        _animation.triggerEvents(
            _actor.components, time, _time, triggeredEvents);
        time = _min + (time - _max);
        _animation.triggerEvents(
            _actor.components, _min - 0.001, time, triggeredEvents);
      } else {
        time = _max;
        if (_time != time) {
          _animation.triggerEvents(
              _actor.components, _time, _max, triggeredEvents);
        }
      }
    } else if (time > _time) {
      _animation.triggerEvents(_actor.components, _time, time, triggeredEvents);
    } else {
      _animation.triggerEvents(_actor.components, time, _time, triggeredEvents);
    }

    // TODO:
    // for(AnimationEventArgs ev in triggeredEvents)
    // {
    //     if (AnimationEvent != null)
    //     {
    //         AnimationEvent(this, ev);
    //     }
    //     _actor.onAnimationEvent(ev);
    // }
    _time = time;
    return triggeredEvents;
  }

  void apply(double mix) {
    _animation.apply(_time, _actor, mix);
  }
}
