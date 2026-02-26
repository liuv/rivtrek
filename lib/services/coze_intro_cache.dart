import 'database_service.dart';

/// 江川向导「此地风土」介绍缓存：按河流+位置持久化在 SQLite 主库，冷启动可用，同一位置不重复请求。
const int _maxEntries = 30;
const String _entrySep = '\u0001';

class CozeIntroCache {
  static final CozeIntroCache instance = CozeIntroCache._();
  CozeIntroCache._();

  final Map<String, _Entry> _map = {};
  bool _loaded = false;

  String _key(String? riverId, String? locationKey) {
    if (riverId == null || locationKey == null) return '';
    return '$riverId$_entrySep$locationKey';
  }

  /// 启动时从 SQLite 加载全部缓存到内存，便于同步 get()
  Future<void> load() async {
    if (_loaded) return;
    final rows = await DatabaseService.instance.getAllCozeIntroCache();
    _map.clear();
    for (final row in rows) {
      final riverId = row['river_id'] as String?;
      final locationKey = row['location_key'] as String?;
      final content = row['content'] as String?;
      final updatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
      if (riverId != null && locationKey != null && content != null) {
        _map[_key(riverId, locationKey)] = _Entry(content: content, updatedAt: updatedAt);
      }
    }
    _loaded = true;
  }

  /// 当前（河流+位置）是否已有缓存；无位置或未加载时视为无缓存
  String? get(String? riverId, String? locationKey) {
    final k = _key(riverId, locationKey);
    if (k.isEmpty) return null;
    return _map[k]?.content;
  }

  /// 写入 SQLite 并更新内存；超过 [_maxEntries] 时由 DB 删最旧
  Future<void> put(String? riverId, String? locationKey, String content) async {
    final k = _key(riverId, locationKey);
    if (k.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await DatabaseService.instance.putCozeIntroCache(riverId, locationKey, content);
    _map[k] = _Entry(content: content, updatedAt: now);
    while (_map.length > _maxEntries) {
      String? oldestKey;
      int oldestT = now;
      for (final e in _map.entries) {
        if (e.value.updatedAt < oldestT) {
          oldestT = e.value.updatedAt;
          oldestKey = e.key;
        }
      }
      if (oldestKey != null) _map.remove(oldestKey);
      else break;
    }
  }
}

class _Entry {
  final String content;
  final int updatedAt;
  _Entry({required this.content, required this.updatedAt});
}
