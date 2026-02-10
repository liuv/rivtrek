// lib/models/river.dart

import 'package:flutter/material.dart';

class River {
  final String id;
  final String name;
  final String description;
  final double totalLengthKm;
  final String themeColor;
  final String masterJsonPath;
  final String pointsJsonPath;
  final int difficulty; // 1-5
  final String iconPath;

  River({
    required this.id,
    required this.name,
    required this.description,
    required this.totalLengthKm,
    required this.themeColor,
    required this.masterJsonPath,
    required this.pointsJsonPath,
    this.difficulty = 3,
    required this.iconPath,
  });

  Color get color => Color(int.parse(themeColor.replaceFirst('#', '0xFF')));

  factory River.fromJson(Map<String, dynamic> json) {
    return River(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      totalLengthKm: json['total_length_km'].toDouble(),
      themeColor: json['theme_color'],
      masterJsonPath: json['master_json_path'],
      pointsJsonPath: json['points_json_path'],
      difficulty: json['difficulty'] ?? 3,
      iconPath: json['icon_path'] ?? '',
    );
  }
}
