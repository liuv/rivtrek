import "dart:math";
import "actor_artboard.dart";
import "actor_color.dart";
import "actor_component.dart";
import "actor_drawable.dart";
import "actor_node.dart";
import "actor_path.dart";
import "math/aabb.dart";
import "math/mat2d.dart";
import "math/vec2d.dart";
import "stream_reader.dart";

class ActorShape extends ActorDrawable {
  final List<ActorStroke> _strokes = <ActorStroke>[];
  final List<ActorFill> _fills = <ActorFill>[];

  ActorFill? get fill => _fills.isNotEmpty ? _fills.first : null;
  ActorStroke? get stroke => _strokes.isNotEmpty ? _strokes.first : null;
  List<ActorFill> get fills => _fills;
  List<ActorStroke> get strokes => _strokes;

  @override
  void update(int dirt) {
    super.update(dirt);
    invalidateShape();
  }

  static ActorShape read(
      ActorArtboard artboard, StreamReader reader, ActorShape component) {
    ActorDrawable.read(artboard, reader, component);

    return component;
  }

  @override
  ActorComponent makeInstance(ActorArtboard resetArtboard) {
    ActorShape instanceShape = resetArtboard.actor.makeShapeNode();
    instanceShape.copyShape(this, resetArtboard);
    return instanceShape;
  }

  void copyShape(ActorShape node, ActorArtboard resetArtboard) {
    copyDrawable(node, resetArtboard);
  }

  @override
  AABB computeAABB() {
    AABB aabb = AABB.fromValues(double.maxFinite, double.maxFinite,
        -double.maxFinite, -double.maxFinite);
    for (final List<ActorShape> clips in clipShapes) {
      for (final ActorShape node in clips) {
        AABB bounds = node.computeAABB();
        if (bounds[0] < aabb[0]) {
          aabb[0] = bounds[0];
        }
        if (bounds[1] < aabb[1]) {
          aabb[1] = bounds[1];
        }
        if (bounds[2] > aabb[2]) {
          aabb[2] = bounds[2];
        }
        if (bounds[3] > aabb[3]) {
          aabb[3] = bounds[3];
        }
      }
    }

    if (children != null) {
      for (final ActorNode node in children!) {
        if (node is ActorBasePath) {
          ActorBasePath path = node as ActorBasePath;
          // This is the axis aligned bounding box in the space of the
          // parent (this case our shape).
          AABB pathAABB = path.getPathAABB();

          // Combine.
          aabb[0] = min(aabb[0], pathAABB[0]);
          aabb[1] = min(aabb[1], pathAABB[1]);

          aabb[2] = max(aabb[2], pathAABB[2]);
          aabb[3] = max(aabb[3], pathAABB[3]);
        }
      }
    }

    double minX = double.maxFinite;
    double minY = double.maxFinite;
    double maxX = -double.maxFinite;
    double maxY = -double.maxFinite;
    Mat2D world = worldTransform;

    double maxStroke = 0.0;
    for (final ActorStroke stroke in _strokes) {
      if (stroke.width > maxStroke) {
        maxStroke = stroke.width;
      }
    }
    double padStroke = maxStroke / 2.0;
    aabb[0] -= padStroke;
    aabb[2] += padStroke;
    aabb[1] -= padStroke;
    aabb[3] += padStroke;

    List<Vec2D> points = [
      Vec2D.fromValues(aabb[0], aabb[1]),
      Vec2D.fromValues(aabb[2], aabb[1]),
      Vec2D.fromValues(aabb[2], aabb[3]),
      Vec2D.fromValues(aabb[0], aabb[3])
    ];
    for (var i = 0; i < points.length; i++) {
      Vec2D pt = points[i];
      Vec2D wp = Vec2D.transformMat2D(pt, pt, world);
      if (wp[0] < minX) {
        minX = wp[0];
      }
      if (wp[1] < minY) {
        minY = wp[1];
      }

      if (wp[0] > maxX) {
        maxX = wp[0];
      }
      if (wp[1] > maxY) {
        maxY = wp[1];
      }
    }
    return AABB.fromValues(minX, minY, maxX, maxY);
  }

  void addStroke(ActorStroke stroke) {
    _strokes.add(stroke);
  }

  void addFill(ActorFill fill) {
    _fills.add(fill);
  }

  @override
  void initializeGraphics() {
    for (final ActorStroke stroke in _strokes) {
      stroke.initializeGraphics();
    }
    for (final ActorFill fill in _fills) {
      fill.initializeGraphics();
    }
  }

  @override
  int get blendModeId {
    return 0;
  }

  @override
  set blendModeId(int value) {}
}
