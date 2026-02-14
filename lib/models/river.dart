// lib/models/river.dart

import 'package:flutter/material.dart';

class River {
  /// 数字主键，便于高效检索（如数据库、索引）
  final int numericId;
  final String id;
  final String name;
  final String description;
  final double totalLengthKm;
  final String themeColor;
  final String masterJsonPath;
  final String pointsJsonPath;
  final int difficulty; // 1-5
  final String iconPath;
  /// 行进距离 → 路径距离：path_km = app_accumulated_km * correctionCoefficient。由各河流 master JSON 的 correction_coefficient 加载，不依赖 config 手配。
  final double correctionCoefficient;

  River({
    required this.numericId,
    required this.id,
    required this.name,
    required this.description,
    required this.totalLengthKm,
    required this.themeColor,
    required this.masterJsonPath,
    required this.pointsJsonPath,
    this.difficulty = 3,
    required this.iconPath,
    this.correctionCoefficient = 1.0,
  });

  River copyWith({double? correctionCoefficient}) {
    return River(
      numericId: numericId,
      id: id,
      name: name,
      description: description,
      totalLengthKm: totalLengthKm,
      themeColor: themeColor,
      masterJsonPath: masterJsonPath,
      pointsJsonPath: pointsJsonPath,
      difficulty: difficulty,
      iconPath: iconPath,
      correctionCoefficient: correctionCoefficient ?? this.correctionCoefficient,
    );
  }

  Color get color => Color(int.parse(themeColor.replaceFirst('#', '0xFF')));

  factory River.fromJson(Map<String, dynamic> json) {
    return River(
      numericId: (json['numeric_id'] as num?)?.toInt() ?? 0,
      id: json['id'],
      name: json['name'],
      description: json['description'],
      totalLengthKm: json['total_length_km'].toDouble(),
      themeColor: json['theme_color'],
      masterJsonPath: json['master_json_path'],
      pointsJsonPath: json['points_json_path'],
      difficulty: json['difficulty'] ?? 3,
      iconPath: json['icon_path'] ?? '',
      correctionCoefficient: (json['correction_coefficient'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
