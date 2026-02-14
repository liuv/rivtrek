import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_stats.dart';
import '../repositories/river_repository.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rivtrek_v1.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE daily_weather ADD COLUMN aqi TEXT DEFAULT "--"');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE daily_activities ADD COLUMN river_id TEXT DEFAULT "yangtze"');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE river_pois (
              river_id TEXT NOT NULL,
              distance_km REAL NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              formatted_address TEXT,
              admin_area TEXT,
              locality TEXT,
              name TEXT,
              PRIMARY KEY (river_id, distance_km)
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('DROP TABLE IF EXISTS river_pois');
          await db.execute('''
            CREATE TABLE river_pois (
              numeric_id INTEGER NOT NULL,
              river_id TEXT NOT NULL,
              distance_km REAL NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              formatted_address TEXT,
              country TEXT,
              province TEXT,
              city TEXT,
              citycode TEXT,
              district TEXT,
              adcode TEXT,
              township TEXT,
              towncode TEXT,
              pois_json TEXT,
              PRIMARY KEY (numeric_id, distance_km)
            )
          ''');
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. 每日步数统计 (高频写)
    await db.execute('''
      CREATE TABLE daily_activities (
        date TEXT,
        river_id TEXT,
        steps INTEGER,
        distance_km REAL,
        accumulated_distance_km REAL,
        PRIMARY KEY (date, river_id)
      )
    ''');

    // 2. 每日天气快照 (每天更新 1-3 次，记录最新)
    await db.execute('''
      CREATE TABLE daily_weather (
        date TEXT PRIMARY KEY,
        wmo_code INTEGER,
        current_temp TEXT,
        max_temp TEXT,
        min_temp TEXT,
        wind_speed REAL,
        city_name TEXT,
        latitude REAL,
        longitude REAL,
        aqi TEXT
      )
    ''');

    // 3. 河流事件记录 (拾遗、祭祀等行为流)
    await db.execute('''
      CREATE TABLE river_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        timestamp INTEGER,
        type TEXT,
        name TEXT,
        description TEXT,
        latitude REAL,
        longitude REAL,
        distance_at_km REAL,
        extra_data TEXT
      )
    ''');

    // 4. 河流里程-POI 表（numeric_id 主键便于索引，river_id 保留字符型便于可读）
    await db.execute('''
      CREATE TABLE river_pois (
        numeric_id INTEGER NOT NULL,
        river_id TEXT NOT NULL,
        distance_km REAL NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        formatted_address TEXT,
        country TEXT,
        province TEXT,
        city TEXT,
        citycode TEXT,
        district TEXT,
        adcode TEXT,
        township TEXT,
        towncode TEXT,
        pois_json TEXT,
        PRIMARY KEY (numeric_id, distance_km)
      )
    ''');
  }

  // --- 写入方法 ---

  Future<int> saveActivity(DailyActivity activity) async {
    final db = await instance.database;
    return await db.insert('daily_activities', activity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> saveWeather(DailyWeather weather) async {
    final db = await instance.database;
    return await db.insert('daily_weather', weather.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> recordEvent(RiverEvent event) async {
    final db = await instance.database;
    return await db.insert('river_events', event.toMap());
  }

  Future<void> insertRiverPois(List<RiverPoi> pois) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final p in pois) {
      batch.insert('river_pois', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // --- 查询方法 ---

  Future<DailyActivity?> getActivityByDate(String date) async {
    final db = await instance.database;
    final maps = await db.query('daily_activities', where: 'date = ?', whereArgs: [date]);
    if (maps.isNotEmpty) return DailyActivity.fromMap(maps.first);
    return null;
  }

  Future<DailyWeather?> getWeatherByDate(String date) async {
    final db = await instance.database;
    final maps = await db.query('daily_weather', where: 'date = ?', whereArgs: [date]);
    if (maps.isNotEmpty) return DailyWeather.fromMap(maps.first);
    return null;
  }

  Future<List<RiverEvent>> getEventsByDate(String date) async {
    final db = await instance.database;
    final result = await db.query('river_events', where: 'date = ?', whereArgs: [date]);
    return result.map((json) => RiverEvent(
      id: json['id'] as int,
      date: json['date'] as String,
      timestamp: json['timestamp'] as int,
      type: RiverEventType.values.firstWhere((e) => e.name == json['type']),
      name: json['name'] as String,
      description: json['description'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      distanceAtKm: json['distance_at_km'] as double,
      extraData: json['extra_data'] as String,
    )).toList();
  }

  Future<List<DailyActivity>> getAllActivities() async {
    final db = await instance.database;
    final result = await db.query('daily_activities');
    return result.map((map) => DailyActivity.fromMap(map)).toList();
  }

  Future<List<DailyWeather>> getAllWeather() async {
    final db = await instance.database;
    final result = await db.query('daily_weather');
    return result.map((map) => DailyWeather.fromMap(map)).toList();
  }

  Future<List<RiverEvent>> getAllEvents() async {
    final db = await instance.database;
    final result = await db.query('river_events', orderBy: 'timestamp ASC');
    return result
        .map((json) => RiverEvent(
              id: json['id'] as int?,
              date: json['date'] as String,
              timestamp: (json['timestamp'] as num).toInt(),
              type: RiverEventType.values.firstWhere(
                (e) => e.name == json['type'],
                orElse: () => RiverEventType.activity,
              ),
              name: json['name'] as String,
              description: json['description'] as String,
              latitude: (json['latitude'] as num).toDouble(),
              longitude: (json['longitude'] as num).toDouble(),
              distanceAtKm: (json['distance_at_km'] as num).toDouble(),
              extraData: json['extra_data'] as String? ?? "{}",
            ))
        .toList();
  }

  /// 按「路径距离」查最近 POI：先按河流缩放因子把行进距离转为 path_km，再取 |distance_km - path_km| 最小的那条（前后各查一次，取更近者），支持线性存储与按变化点压缩
  Future<RiverPoi?> getNearestPoi(String riverId, double accumulatedKm) async {
    await RiverRepository.instance.ensureLoaded();
    final river = RiverRepository.instance.getRiverById(riverId);
    final numericId = RiverRepository.instance.getRiverSlugToNumericId()[riverId];
    if (numericId == null) return null;
    final pathKm = accumulatedKm * (river?.correctionCoefficient ?? 1.0);
    final db = await instance.database;
    final before = await db.query(
      'river_pois',
      where: 'numeric_id = ? AND distance_km <= ?',
      whereArgs: [numericId, pathKm],
      orderBy: 'distance_km DESC',
      limit: 1,
    );
    final after = await db.query(
      'river_pois',
      where: 'numeric_id = ? AND distance_km >= ?',
      whereArgs: [numericId, pathKm],
      orderBy: 'distance_km ASC',
      limit: 1,
    );
    RiverPoi? pick(Map<String, dynamic> row) => RiverPoi.fromMap(row);
    if (before.isEmpty) return after.isEmpty ? null : pick(after.first);
    if (after.isEmpty) return pick(before.first);
    final dBefore = (before.first['distance_km'] as num).toDouble();
    final dAfter = (after.first['distance_km'] as num).toDouble();
    return pick((pathKm - dBefore) <= (dAfter - pathKm) ? before.first : after.first);
  }
}
