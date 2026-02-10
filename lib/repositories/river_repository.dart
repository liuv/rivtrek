// lib/repositories/river_repository.dart

import '../models/river.dart';

class RiverRepository {
  static final RiverRepository instance = RiverRepository._();
  RiverRepository._();

  final List<River> _rivers = [
    River(
      id: 'yangtze',
      name: '长江',
      description: '唯见长江天际流，从雪山走来，向东海奔腾，横贯中华大地。',
      totalLengthKm: 6387.0,
      themeColor: '#2196F3',
      masterJsonPath: 'assets/json/rivers/yangtze_master.json',
      pointsJsonPath: 'assets/json/rivers/yangtze_points.json',
      difficulty: 4,
      iconPath: 'assets/icons/river_yangtze.png',
    ),
    River(
      id: 'yellow_river',
      name: '黄河',
      description: '九曲黄河万里沙，奔流到海不复回，中华民族的摇篮。',
      totalLengthKm: 5464.0,
      themeColor: '#FF9800',
      masterJsonPath: 'assets/json/rivers/yellow_river_master.json',
      pointsJsonPath: 'assets/json/rivers/yellow_river_points.json',
      difficulty: 5,
      iconPath: 'assets/icons/river_yellow.png',
    ),
    River(
      id: 'songhua_river',
      name: '松花江',
      description: '北国明珠，穿越林海雪原，感受冰雪与森林的交响。',
      totalLengthKm: 2309.0,
      themeColor: '#00BCD4',
      masterJsonPath: 'assets/json/rivers/songhua_river_master.json',
      pointsJsonPath: 'assets/json/rivers/songhua_river_points.json',
      difficulty: 3,
      iconPath: 'assets/icons/river_songhua.png',
    ),
  ];

  Future<List<River>> getAvailableRivers() async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 300));
    return _rivers;
  }

  River? getRiverById(String id) {
    try {
      return _rivers.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
