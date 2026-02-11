class RiverFullData {
  final String gameChallengeName;
  final String challengeId;
  final double totalLengthKm;
  final int totalSections;
  final List<ChallengeSection> challengeSections;

  RiverFullData({
    required this.gameChallengeName,
    required this.challengeId,
    required this.totalLengthKm,
    required this.totalSections,
    required this.challengeSections,
  });

  factory RiverFullData.fromJson(Map<String, dynamic> json) {
    return RiverFullData(
      gameChallengeName: json['game_challenge_name'],
      challengeId: json['challenge_id'],
      totalLengthKm: (json['total_length_km'] as num).toDouble(),
      totalSections: json['total_sections'],
      challengeSections: (json['challenge_sections'] as List)
          .map((e) => ChallengeSection.fromJson(e))
          .toList(),
    );
  }
}

class ChallengeSection {
  final int sectionId;
  final String sectionName;
  final double sectionLengthKm;
  final String flowArea;
  final String themeColor;
  final List<SubSection> subSections;

  ChallengeSection({
    required this.sectionId,
    required this.sectionName,
    required this.sectionLengthKm,
    required this.flowArea,
    required this.themeColor,
    required this.subSections,
  });

  factory ChallengeSection.fromJson(Map<String, dynamic> json) {
    return ChallengeSection(
      sectionId: json['section_id'],
      sectionName: json['section_name'],
      sectionLengthKm: (json['section_length_km'] as num).toDouble(),
      flowArea: json['flow_area'],
      themeColor: json['theme_color'],
      subSections: (json['sub_sections'] as List)
          .map((e) => SubSection.fromJson(e))
          .toList(),
    );
  }
}

class SubSection {
  final int subSectionId;
  final String subSectionName;
  final String startPoint;
  final String endPoint;
  final double subSectionLengthKm;
  final double accumulatedLengthKm;
  final String subSectionDesc;
  final Achievement? achievement;

  SubSection({
    required this.subSectionId,
    required this.subSectionName,
    required this.startPoint,
    required this.endPoint,
    required this.subSectionLengthKm,
    required this.accumulatedLengthKm,
    required this.subSectionDesc,
    this.achievement,
  });

  factory SubSection.fromJson(Map<String, dynamic> json) {
    return SubSection(
      subSectionId: json['sub_section_id'],
      subSectionName: json['sub_section_name'],
      startPoint: json['start_point'],
      endPoint: json['end_point'],
      subSectionLengthKm: (json['sub_section_length_km'] as num).toDouble(),
      accumulatedLengthKm: (json['accumulated_length_km'] as num).toDouble(),
      subSectionDesc: json['sub_section_desc'],
      achievement: json['achievement'] != null ? Achievement.fromJson(json['achievement']) : null,
    );
  }
}

class Achievement {
  final String achievementName;
  final String achievementDesc;
  final String? medalIcon;

  Achievement({
    required this.achievementName,
    required this.achievementDesc,
    this.medalIcon,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      achievementName: json['achievement_name'] ?? '',
      achievementDesc: json['achievement_desc'] ?? '',
      medalIcon: json['medal_icon'],
    );
  }
}

class RiverPointsData {
  final String riverName;
  final double correctionCoefficient;
  final List<List<List<double>>> sectionsPoints;

  RiverPointsData({
    required this.riverName,
    required this.correctionCoefficient,
    required this.sectionsPoints,
  });

  factory RiverPointsData.fromJson(Map<String, dynamic> json) {
    return RiverPointsData(
      riverName: json['river_name'],
      correctionCoefficient: (json['correction_coefficient'] as num).toDouble(),
      sectionsPoints: (json['sections_points'] as List)
          .map((s) => (s as List)
              .map((p) => (p as List).map((c) => (c as num).toDouble()).toList())
              .toList())
          .toList(),
    );
  }
}
