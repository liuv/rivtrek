import 'package:flutter/material.dart';

enum RiverPathMode {
  procedural,
  realPath,
}

enum RiverStyle {
  classic,
  ink,
  aurora,
}

class RiverSettings extends ChangeNotifier {
  static final RiverSettings instance = RiverSettings();

  RiverPathMode _pathMode;
  RiverStyle _style;
  double _speed;
  double _turbulence;
  double _width;

  RiverSettings({
    RiverPathMode pathMode = RiverPathMode.procedural,
    RiverStyle style = RiverStyle.classic,
    double speed = 0.3,
    double turbulence = 0.6,
    double width = 0.18,
  })  : _pathMode = pathMode,
        _style = style,
        _speed = speed,
        _turbulence = turbulence,
        _width = width;

  RiverPathMode get pathMode => _pathMode;
  RiverStyle get style => _style;
  double get speed => _speed;
  double get turbulence => _turbulence;
  double get width => _width;

  void update({
    RiverPathMode? pathMode,
    RiverStyle? style,
    double? speed,
    double? turbulence,
    double? width,
  }) {
    _pathMode = pathMode ?? _pathMode;
    _style = style ?? _style;
    _speed = speed ?? _speed;
    _turbulence = turbulence ?? _turbulence;
    _width = width ?? _width;
    notifyListeners();
  }
}
