// lib/models/flow_models.dart

class Lantern {
  final double id;
  double localY; 
  final double randomX; 
  final double wobbleSpeed;
  final double wobblePhase;
  final double scaleBase;
  double rotation = 0;

  Lantern({
    required this.id,
    this.localY = -1.2,
    required this.randomX,
    required this.wobbleSpeed,
    required this.wobblePhase,
    required this.scaleBase,
  });
}

class Blessing {
  final String text;
  double localY;
  double opacity = 1.0;
  double blur = 0.0;
  final double randomX;

  Blessing({
    required this.text,
    required this.localY,
    required this.randomX,
  });
}

/// 漂流瓶（水畔寄书），与河灯类似随水流漂动
class Bottle {
  final double id;
  double localY;
  final double randomX;
  final double wobbleSpeed;
  final double wobblePhase;
  final double scaleBase;
  double rotation = 0;

  Bottle({
    required this.id,
    this.localY = -1.2,
    required this.randomX,
    required this.wobbleSpeed,
    required this.wobblePhase,
    required this.scaleBase,
  });
}
