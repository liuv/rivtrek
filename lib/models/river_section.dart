import 'package:flutter/material.dart';

class RiverSection {
  final String name;
  final String themeColor;
  final List<SubSection> subSections;
  RiverSection.fromJson(Map<String, dynamic> json)
      : name = json['section_name'],
        themeColor = json['theme_color'],
        subSections = (json['sub_sections'] as List)
            .map((s) => SubSection.fromJson(s, json['theme_color']))
            .toList();
}

class SubSection {
  final String name;
  final double accumulatedLength;
  final double baseFlowSpeed;
  final int difficulty;
  final Color color;
  final String? medalIcon;

  SubSection.fromJson(Map<String, dynamic> json, String defaultColor)
      : name = json['sub_section_name'],
        accumulatedLength = json['accumulated_length_km'].toDouble(),
        baseFlowSpeed = json['base_flow_speed'].toDouble(),
        difficulty = json['difficulty_rating'],
        medalIcon = json['achievement']?['medal_icon'],
        color = Color(int.parse(defaultColor.replaceFirst('#', '0xFF')));
}
