import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_stats.dart';
import '../repositories/river_repository.dart';

/// 主库：仅存动态数据（步数、天气、事件）。基础数据（POI 等）使用独立库 [baseDatabase]（rivtrek_base.db），不合并、解耦。
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static Database? _baseDatabase;

  /// 基础数据库文件名，可存 POI、今后其他静态/配置数据等
  static const String _baseDbFileName = 'rivtrek_base.db';
  static const String _baseDbAssetPath = 'assets/db/rivtrek_base.db';

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initMainDB('rivtrek_v1.db');
    return _database!;
  }

  Future<Database> _initMainDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createMainDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE daily_weather ADD COLUMN aqi TEXT DEFAULT "--"');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE daily_activities ADD COLUMN river_id TEXT DEFAULT "yangtze"');
        }
        if (oldVersion < 6) {
          await db.execute('DROP TABLE IF EXISTS river_pois');
        }
      },
    );
  }

  Future _createMainDB(Database db, int version) async {
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
  }

  /// 基础数据库（POI 等静态数据，只读）。每次使用前从 asset 强制覆盖本地文件，覆盖安装后也会得到新包内最新数据。
  Future<Database?> get baseDatabase async => _getBaseDatabase();

  Future<Database?> _getBaseDatabase() async {
    if (_baseDatabase != null) return _baseDatabase;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _baseDbFileName);
    try {
      final byteData = await rootBundle.load(_baseDbAssetPath);
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
      _baseDatabase = await openDatabase(path);
      return _baseDatabase;
    } catch (_) {
      return null;
    }
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

  /// 写入基础数据库的 river_pois 表（脚本生成后一般不需在 App 内写入，仅当有运行时导入需求时使用）。
  Future<void> insertRiverPois(List<RiverPoi> pois) async {
    final db = await instance.baseDatabase;
    if (db == null) return;
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

  /// 按「路径距离」查最近 POI（本地 POI 库查询，非网络请求）。path_km = accumulated_km * correctionCoefficient，前后各查一次取更近者。
  /// 若基础库未就绪或无 river_pois 表（未导入 POI 资源），静默返回 null，不抛错。
  Future<RiverPoi?> getNearestPoi(String riverId, double accumulatedKm) async {
    try {
      await RiverRepository.instance.ensureLoaded();
      final river = RiverRepository.instance.getRiverById(riverId);
      final numericId = RiverRepository.instance.getRiverSlugToNumericId()[riverId];
      if (numericId == null) return null;
      final pathKm = accumulatedKm * (river?.correctionCoefficient ?? 1.0);
      final db = await instance.baseDatabase;
      if (db == null) return null;
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
    } catch (_) {
      return null;
    }
  }
}
