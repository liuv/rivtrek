import "actor_artboard.dart";
import "actor_axis_constraint.dart";
import "actor_node.dart";
import "math/mat2d.dart";
import "math/transform_components.dart";
import "stream_reader.dart";
import "transform_space.dart";

class ActorScaleConstraint extends ActorAxisConstraint {
  final TransformComponents _componentsA = TransformComponents();
  final TransformComponents _componentsB = TransformComponents();

  ActorScaleConstraint() : super();

  static ActorScaleConstraint read(ActorArtboard artboard, StreamReader reader,
      ActorScaleConstraint? component) {
    component ??= ActorScaleConstraint();
    ActorAxisConstraint.read(artboard, reader, component);
    return component;
  }

  @override
  makeInstance(ActorArtboard resetArtboard) {
    ActorScaleConstraint node = ActorScaleConstraint();
    node.copyAxisConstraint(this, resetArtboard);
    return node;
  }

  @override
  constrain(ActorNode node) {
    ActorNode t = target as ActorNode;
    ActorNode p = node;
    ActorNode grandParent = p.parent!;

    Mat2D transformA = p.worldTransform;
    Mat2D transformB = Mat2D();
    Mat2D.decompose(transformA, _componentsA);
    Mat2D.copy(transformB, t.worldTransform);
    if (sourceSpace == TransformSpace.Local) {
      ActorNode sourceGrandParent = t.parent!;
      Mat2D inverse = Mat2D();
      Mat2D.invert(inverse, sourceGrandParent.worldTransform);
      Mat2D.multiply(transformB, inverse, transformB);
    }
    Mat2D.decompose(transformB, _componentsB);

    if (!copyX) {
      _componentsB[2] =
          destSpace == TransformSpace.Local ? 1.0 : _componentsA[2];
    } else {
      _componentsB[2] *= scaleX;
      if (offset) {
        _componentsB[2] *= p.scaleX;
      }
    }

    if (!copyY) {
      _componentsB[3] =
          destSpace == TransformSpace.Local ? 0.0 : _componentsA[3];
    } else {
      _componentsB[3] *= scaleY;

      if (offset) {
        _componentsB[3] *= p.scaleY;
      }
    }

    if (destSpace == TransformSpace.Local) {
      // Destination space is in parent transform coordinates.
      // Recompose the parent local transform and get it in world, then decompose the world for interpolation.
      Mat2D.compose(transformB, _componentsB);
      Mat2D.multiply(transformB, grandParent.worldTransform, transformB);
      Mat2D.decompose(transformB, _componentsB);
    }

    bool clampLocal = minMaxSpace == TransformSpace.Local;
    if (clampLocal) {
      // Apply min max in local space, so transform to local coordinates first.
      Mat2D.compose(transformB, _componentsB);
      Mat2D inverse = Mat2D();
      Mat2D.invert(inverse, grandParent.worldTransform);
      Mat2D.multiply(transformB, inverse, transformB);
      Mat2D.decompose(transformB, _componentsB);
    }
    if (enableMaxX && _componentsB[2] > maxX) {
      _componentsB[2] = maxX;
    }
    if (enableMinX && _componentsB[2] < minX) {
      _componentsB[2] = minX;
    }
    if (enableMaxY && _componentsB[3] > maxY) {
      _componentsB[3] = maxY;
    }
    if (enableMinY && _componentsB[3] < minY) {
      _componentsB[3] = minY;
    }
    if (clampLocal) {
      // Transform back to world.
      Mat2D.compose(transformB, _componentsB);
      Mat2D.multiply(transformB, grandParent.worldTransform, transformB);
      Mat2D.decompose(transformB, _componentsB);
    }

    double ti = 1.0 - strength;

    _componentsB[4] = _componentsA[4];
    _componentsB[0] = _componentsA[0];
    _componentsB[1] = _componentsA[1];
    _componentsB[2] = _componentsA[2] * ti + _componentsB[2] * strength;
    _componentsB[3] = _componentsA[3] * ti + _componentsB[3] * strength;
    _componentsB[5] = _componentsA[5];

    Mat2D.compose(p.worldTransform, _componentsB);
  }

  @override
  void update(int dirt) {}
  @override
  void completeResolve() {}
}
