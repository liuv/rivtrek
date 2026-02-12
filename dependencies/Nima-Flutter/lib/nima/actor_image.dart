import 'dart:typed_data';

import "actor.dart";
import "actor_bone_base.dart";
import "actor_component.dart";
import "actor_node.dart";
import "math/mat2d.dart";
import "math/vec2d.dart";
import "readers/stream_reader.dart";

enum BlendModes { Normal, Multiply, Screen, Additive }

class BoneConnection {
  int boneIdx = 0;
  late ActorNode node;
  Mat2D bind = Mat2D();
  Mat2D inverseBind = Mat2D();
}

class SequenceFrame {
  final int _atlasIndex;
  final int _offset;
  SequenceFrame(this._atlasIndex, this._offset);

  @override
  String toString() {
    return "(" + _atlasIndex.toString() + ", " + _offset.toString() + ")";
  }

  int get atlasIndex {
    return _atlasIndex;
  }

  int get offset {
    return _offset;
  }
}

class ActorImage extends ActorNode {
  // Editor set draw index.
  int drawOrder = 0;
  // Computed draw index in the image list.
  int drawIndex = 0;
  BlendModes _blendMode = BlendModes.Normal;
  int _textureIndex = -1;
  Float32List _vertices = Float32List(0);
  Uint16List _triangles = Uint16List(0);
  int _vertexCount = 0;
  int _triangleCount = 0;
  Float32List? _animationDeformedVertices;
  bool isVertexDeformDirty = false;
  List<BoneConnection>? _boneConnections;
  Float32List _boneMatrices = Float32List(0);
  List<SequenceFrame> _sequenceFrames = [];
  Float32List _sequenceUVs = Float32List(0);
  int _sequenceFrame = 0;

  int get sequenceFrame {
    return _sequenceFrame;
  }

  Float32List get sequenceUVs {
    return _sequenceUVs;
  }

  List<SequenceFrame> get sequenceFrames {
    return _sequenceFrames;
  }

  set sequenceFrame(int value) {
    _sequenceFrame = value;
  }

  int get connectedBoneCount {
    return _boneConnections?.length ?? 0;
  }

  List<BoneConnection>? get boneConnections {
    return _boneConnections;
  }

  int get textureIndex {
    return _textureIndex;
  }

  BlendModes get blendMode {
    return _blendMode;
  }

  int get vertexCount {
    return _vertexCount;
  }

  int get triangleCount {
    return _triangleCount;
  }

  Uint16List get triangles {
    return _triangles;
  }

  Float32List get vertices {
    return _vertices;
  }

  int get vertexPositionOffset {
    return 0;
  }

  int get vertexUVOffset {
    return 2;
  }

  int get vertexBoneIndexOffset {
    return 4;
  }

  int get vertexBoneWeightOffset {
    return 8;
  }

  int get vertexStride {
    return 12;
  }

  bool get isSkinned {
    return _boneConnections != null;
  }

  bool get doesAnimationVertexDeform {
    return _animationDeformedVertices != null;
  }

  set doesAnimationVertexDeform(bool value) {
    if (value) {
      if (_animationDeformedVertices == null ||
          _animationDeformedVertices!.length != _vertexCount * 2) {
        _animationDeformedVertices = Float32List(_vertexCount * 2);
        // Copy the deform verts from the rig verts.
        int writeIdx = 0;
        int readIdx = 0;
        int readStride = vertexStride;
        for (int i = 0; i < _vertexCount; i++) {
          _animationDeformedVertices![writeIdx++] = _vertices[readIdx];
          _animationDeformedVertices![writeIdx++] = _vertices[readIdx + 1];
          readIdx += readStride;
        }
      }
    } else {
      _animationDeformedVertices = null;
    }
  }

  Float32List? get animationDeformedVertices {
    return _animationDeformedVertices;
  }

  ActorImage();

  void disposeGeometry() {
    // Delete vertices only if we do not vertex deform at runtime.
    _triangles = Uint16List(0);
  }

  // We don't do this at initialization as some engines (like Unity)
  // don't need us to handle the bone matrix transforms ourselves.
  // This helps keep memory a little lower when this code runs in those engines.
  void instanceBoneMatrices() {
    if (_boneConnections != null &&
        _boneMatrices.length != _boneConnections!.length * 6 + 6) {
      _boneMatrices = Float32List(_boneConnections!.length * 6 + 6);
      _boneMatrices[0] = 1.0;
      _boneMatrices[1] = 0.0;
      _boneMatrices[2] = 0.0;
      _boneMatrices[3] = 1.0;
      _boneMatrices[4] = 0.0;
      _boneMatrices[5] = 0.0;
    }
  }

  Float32List get boneInfluenceMatrices {
    instanceBoneMatrices();

    Mat2D mat = Mat2D();
    int bidx = 6;
    if (_boneConnections != null) {
      for (final BoneConnection bc in _boneConnections!) {
        Mat2D.multiply(mat, bc.node.worldTransform, bc.inverseBind);

        _boneMatrices[bidx++] = mat[0];
        _boneMatrices[bidx++] = mat[1];
        _boneMatrices[bidx++] = mat[2];
        _boneMatrices[bidx++] = mat[3];
        _boneMatrices[bidx++] = mat[4];
        _boneMatrices[bidx++] = mat[5];
      }
    }
    return _boneMatrices;
  }

  Float32List get boneTransformMatrices {
    instanceBoneMatrices();

    int bidx = 6;
    if (_boneConnections != null) {
      for (final BoneConnection bc in _boneConnections!) {
        Mat2D mat = bc.node.worldTransform;

        _boneMatrices[bidx++] = mat[0];
        _boneMatrices[bidx++] = mat[1];
        _boneMatrices[bidx++] = mat[2];
        _boneMatrices[bidx++] = mat[3];
        _boneMatrices[bidx++] = mat[4];
        _boneMatrices[bidx++] = mat[5];
      }
    }
    return _boneMatrices;
  }

  static ActorImage read(Actor actor, StreamReader reader, ActorImage? node) {
    node ??= ActorImage();

    ActorNode.read(actor, reader, node);

    bool isVisible = reader.readBool("isVisible");
    if (isVisible) {
      int blendModeId = reader.readUint8("blendMode");
      BlendModes blendMode = BlendModes.Normal;
      switch (blendModeId) {
        case 0:
          blendMode = BlendModes.Normal;
          break;
        case 1:
          blendMode = BlendModes.Multiply;
          break;
        case 2:
          blendMode = BlendModes.Screen;
          break;
        case 3:
          blendMode = BlendModes.Additive;
          break;
      }
      node._blendMode = blendMode;
      node.drawOrder = reader.readUint16("drawOrder");
      node._textureIndex = reader.readUint8("atlas");

      reader.openArray("bones");
      int numConnectedBones = reader.readUint8Length();
      if (numConnectedBones != 0) {
        node._boneConnections =
            List<BoneConnection>.generate(numConnectedBones, (i) => BoneConnection());

        for (int i = 0; i < numConnectedBones; i++) {
          reader.openObject("bone");
          BoneConnection bc = node._boneConnections![i];
          bc.boneIdx = reader.readId("id");
          reader.readFloat32ArrayOffset(bc.bind.values, 6, 0, "bind");
          reader.closeObject();
          Mat2D.invert(bc.inverseBind, bc.bind);
        }
        reader.closeArray();

        Mat2D worldOverride = Mat2D();
        reader.readFloat32ArrayOffset(
            worldOverride.values, 6, 0, "worldTransform");
        node.worldTransformOverride = worldOverride;
      } else {
        // Close the JSON Array opened above to restore reader state.
        reader.closeArray();
      }

      int numVertices = reader.readUint32("numVertices");
      int vertexStride = numConnectedBones > 0 ? 12 : 4;
      node._vertexCount = numVertices;
      node._vertices = Float32List(numVertices * vertexStride);
      reader.readFloat32ArrayOffset(
          node._vertices, node._vertices.length, 0, "vertices");

      int numTris = reader.readUint32("numTriangles");
      node._triangles = Uint16List(numTris * 3);
      node._triangleCount = numTris;
      reader.readUint16Array(
          node._triangles, node._triangles.length, 0, "triangles");
    }

    return node;
  }

  static ActorImage readSequence(
      Actor actor, StreamReader reader, ActorImage node) {
    ActorImage.read(actor, reader, node);

    if (node._textureIndex != -1) {
      reader.openArray("frames");
      int frameAssetCount = reader.readUint16Length();
      // node._sequenceFrames = [];
      Float32List uvs = Float32List(node._vertexCount * 2 * frameAssetCount);
      int uvStride = node._vertexCount * 2;
      node._sequenceUVs = uvs;
      SequenceFrame firstFrame = SequenceFrame(node._textureIndex, 0);
      node._sequenceFrames = <SequenceFrame>[];
      node._sequenceFrames.add(firstFrame);
      int readIdx = 2;
      int writeIdx = 0;
      int vertexStride = 4;
      if (node._boneConnections != null && node._boneConnections!.isNotEmpty) {
        vertexStride = 12;
      }
      for (int i = 0; i < node._vertexCount; i++) {
        uvs[writeIdx++] = node._vertices[readIdx];
        uvs[writeIdx++] = node._vertices[readIdx + 1];
        readIdx += vertexStride;
      }

      int offset = uvStride;
      for (int i = 1; i < frameAssetCount; i++) {
        reader.openObject("frame");

        SequenceFrame frame =
            SequenceFrame(reader.readUint8("atlas"), offset * 4);
        node._sequenceFrames.add(frame);
        reader.readFloat32ArrayOffset(uvs, uvStride, offset, "uv");
        offset += uvStride;

        reader.closeObject();
      }

      reader.closeArray();
    }

    return node;
  }

  @override
  void resolveComponentIndices(List<ActorComponent> components) {
    super.resolveComponentIndices(components);
    if (_boneConnections != null) {
      for (int i = 0; i < _boneConnections!.length; i++) {
        BoneConnection bc = _boneConnections![i];
        bc.node = components[bc.boneIdx] as ActorNode;
        ActorBoneBase bone = bc.node as ActorBoneBase;
        bone.isConnectedToImage = true;
      }
    }
  }

  @override
  ActorComponent makeInstance(Actor resetActor) {
    ActorImage instanceNode = ActorImage();
    instanceNode.copyImage(this, resetActor);
    return instanceNode;
  }

  void copyImage(ActorImage node, Actor resetActor) {
    copyNode(node, resetActor);

    drawOrder = node.drawOrder;
    _blendMode = node._blendMode;
    _textureIndex = node._textureIndex;
    _vertexCount = node._vertexCount;
    _triangleCount = node._triangleCount;
    _vertices = node._vertices;
    _triangles = node._triangles;
    if (node._animationDeformedVertices != null) {
      _animationDeformedVertices =
          Float32List.fromList(node._animationDeformedVertices!);
    }

    if (node._boneConnections != null) {
      _boneConnections =
          List<BoneConnection>.generate(node._boneConnections!.length, (i) => BoneConnection());
      for (int i = 0; i < node._boneConnections!.length; i++) {
        BoneConnection bc = _boneConnections![i];
        bc.boneIdx = node._boneConnections![i].boneIdx;
        Mat2D.copy(bc.bind, node._boneConnections![i].bind);
        Mat2D.copy(bc.inverseBind, node._boneConnections![i].inverseBind);
      }
    }
  }

  void transformBind(Mat2D xform) {
    if (_boneConnections != null) {
      for (final BoneConnection bc in _boneConnections!) {
        Mat2D.multiply(bc.bind, xform, bc.bind);
        Mat2D.invert(bc.inverseBind, bc.bind);
      }
    }
  }

  Float32List makeVertexPositionBuffer() {
    return Float32List(_vertexCount * 2);
  }

  Float32List makeVertexUVBuffer() {
    return Float32List(_vertexCount * 2);
  }

  void transformDeformVertices(Mat2D wt) {
    Float32List? fv = _animationDeformedVertices;
    if (fv == null) {
      return;
    }

    int vidx = 0;
    for (int j = 0; j < _vertexCount; j++) {
      double x = fv[vidx];
      double y = fv[vidx + 1];

      fv[vidx] = wt[0] * x + wt[2] * y + wt[4];
      fv[vidx + 1] = wt[1] * x + wt[3] * y + wt[5];

      vidx += 2;
    }
  }

  void updateVertexUVBuffer(Float32List buffer) {
    int readIdx = vertexUVOffset;
    int writeIdx = 0;
    int stride = vertexStride;

    Float32List v = _vertices;
    for (int i = 0; i < _vertexCount; i++) {
      buffer[writeIdx++] = v[readIdx];
      buffer[writeIdx++] = v[readIdx + 1];
      readIdx += stride;
    }
  }

  void updateVertexPositionBuffer(
      Float32List buffer, bool isSkinnedDeformInWorld) {
    Mat2D worldTransform = this.worldTransform;
    int readIdx = 0;
    int writeIdx = 0;

    Float32List? v = _animationDeformedVertices;
    if (v == null) {
      return;
    }
    int stride = 2;

    if (isSkinned) {
      Float32List boneTransforms = boneInfluenceMatrices;

      //Mat2D inverseWorldTransform = Mat2D.Invert(new Mat2D(), worldTransform);
      Float32List influenceMatrix =
          Float32List.fromList([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);

      int boneIndexOffset = vertexBoneIndexOffset;
      int weightOffset = vertexBoneWeightOffset;
      for (int i = 0; i < _vertexCount; i++) {
        double x = v[readIdx];
        double y = v[readIdx + 1];

        double px, py;

        if (isSkinnedDeformInWorld) {
          px = x;
          py = y;
        } else {
          px =
              worldTransform[0] * x + worldTransform[2] * y + worldTransform[4];
          py =
              worldTransform[1] * x + worldTransform[3] * y + worldTransform[5];
        }

        influenceMatrix[0] = influenceMatrix[1] = influenceMatrix[2] =
            influenceMatrix[3] = influenceMatrix[4] = influenceMatrix[5] = 0.0;

        for (int wi = 0; wi < 4; wi++) {
          int boneIndex = _vertices[boneIndexOffset + wi].toInt();
          double weight = _vertices[weightOffset + wi];

          int boneTransformIndex = boneIndex * 6;
          for (int j = 0; j < 6; j++) {
            influenceMatrix[j] +=
                boneTransforms[boneTransformIndex + j] * weight;
          }
        }

        x = influenceMatrix[0] * px +
            influenceMatrix[2] * py +
            influenceMatrix[4];
        y = influenceMatrix[1] * px +
            influenceMatrix[3] * py +
            influenceMatrix[5];

        readIdx += stride;
        boneIndexOffset += vertexStride;
        weightOffset += vertexStride;

        buffer[writeIdx++] = x;
        buffer[writeIdx++] = y;
      }
    } else {
      Vec2D tempVec = Vec2D();
      for (int i = 0; i < _vertexCount; i++) {
        tempVec[0] = v[readIdx];
        tempVec[1] = v[readIdx + 1];
        Vec2D.transformMat2D(tempVec, tempVec, worldTransform);
        readIdx += stride;

        buffer[writeIdx++] = tempVec[0];
        buffer[writeIdx++] = tempVec[1];
      }
    }
  }
}
