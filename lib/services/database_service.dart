import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_stats.dart';

/// 主库：仅存动态数据（步数、天气、事件）。基础数据（POI 等）使用独立库 [baseDatabase]（rivtrek_base.db），不合并、解耦。
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static Database? _baseDatabase;

  /// 单次初始化，避免多路并发复制 asset/打开导致竞态或重复失败
  static Future<Database?>? _baseDatabaseFuture;

  /// 基础数据库文件名，可存 POI、今后其他静态/配置数据等
  static const String _baseDbFileName = 'rivtrek_base.db';
  static const String _baseDbAssetPath = 'assets/db/rivtrek_base.db';

  /// 与 asset 中 rivtrek_base.db 对应；更新 POI 并重新打库后请 +1，以便安装/升级后覆盖旧文件
  static const int _baseDbAssetVersion = 3;
  static const String _prefKeyBaseDbVersion = 'rivtrek_base_asset_version';

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
          await db.execute(
              'ALTER TABLE daily_weather ADD COLUMN aqi TEXT DEFAULT "--"');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE daily_activities ADD COLUMN river_id TEXT DEFAULT "yangtze"');
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

  /// 基础数据库（POI 等静态数据，只读）。仅「首次安装或 asset 版本升级」时从 asset 拷贝到本地，其余直接打开已拷贝文件，避免每次启动都拷贝。
  /// 使用单次初始化：多路并发调用共用一个 init Future，避免竞态。
  Future<Database?> get baseDatabase async => _getBaseDatabase();

  Future<Database?> _getBaseDatabase() async {
    if (_baseDatabase != null) return _baseDatabase;
    _baseDatabaseFuture ??= _openBaseDatabaseOnce();
    final db = await _baseDatabaseFuture!;
    if (db != null)
      _baseDatabase = db;
    else
      _baseDatabaseFuture = null; // 失败时清空，下次调用可重试
    return db;
  }

  Future<Database?> _openBaseDatabaseOnce() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _baseDbFileName);
    final file = File(path);
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt(_prefKeyBaseDbVersion) ?? 0;
      final needCopy =
          !file.existsSync() || storedVersion < _baseDbAssetVersion;

      if (needCopy) {
        final byteData = await rootBundle.load(_baseDbAssetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
        await prefs.setInt(_prefKeyBaseDbVersion, _baseDbAssetVersion);
      }

      return await openDatabase(path, readOnly: true);
    } catch (e) {
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

  // 基础库 rivtrek_base.db 为只读（从 asset 复制后仅做查询），App 内不写入。POI 数据由 tools/fetch_river_pois.py 生成后放入 assets/db/。

  // --- 查询方法 ---

  Future<DailyActivity?> getActivityByDate(String date) async {
    final db = await instance.database;
    final maps = await db
        .query('daily_activities', where: 'date = ?', whereArgs: [date]);
    if (maps.isNotEmpty) return DailyActivity.fromMap(maps.first);
    return null;
  }

  Future<DailyWeather?> getWeatherByDate(String date) async {
    final db = await instance.database;
    final maps =
        await db.query('daily_weather', where: 'date = ?', whereArgs: [date]);
    if (maps.isNotEmpty) return DailyWeather.fromMap(maps.first);
    return null;
  }

  Future<List<RiverEvent>> getEventsByDate(String date) async {
    final db = await instance.database;
    final result =
        await db.query('river_events', where: 'date = ?', whereArgs: [date]);
    return result
        .map((json) => RiverEvent(
              id: json['id'] as int,
              date: json['date'] as String,
              timestamp: json['timestamp'] as int,
              type: RiverEventType.values
                  .firstWhere((e) => e.name == json['type']),
              name: json['name'] as String,
              description: json['description'] as String,
              latitude: json['latitude'] as double,
              longitude: json['longitude'] as double,
              distanceAtKm: json['distance_at_km'] as double,
              extraData: json['extra_data'] as String,
            ))
        .toList();
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

  /// 仅返回河灯、漂流瓶等漂流类事件（用于虚拟源头时间戳渲染）
  Future<List<RiverEvent>> getDriftEvents() async {
    final all = await getAllEvents();
    return all
        .where((e) =>
            e.type == RiverEventType.activity &&
            (e.name == '放河灯' || e.name == '水畔寄书'))
        .toList();
  }

  /// 按「行进距离」（挑战累计里程）查最近 POI，使用数字主键 [numericId] 查库，避免字符串 id 的精确匹配/空格等问题。
  /// river_pois.distance_km 与 fetch_river_pois 写入一致，为挑战里程，故直接用 accumulatedKm 查，不乘修正系数。
  /// 若基础库未就绪、无 river_pois 表，静默返回 null，不抛错。
  Future<RiverPoi?> getNearestPoi(int numericId, double accumulatedKm) async {
    try {
      final pathKm = accumulatedKm;
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
      if (before.isEmpty && after.isEmpty) return null;
      if (before.isEmpty) return pick(after.first);
      if (after.isEmpty) return pick(before.first);
      final dBefore = (before.first['distance_km'] as num).toDouble();
      final dAfter = (after.first['distance_km'] as num).toDouble();
      final useBefore = (pathKm - dBefore) <= (dAfter - pathKm);
      return pick(useBefore ? before.first : after.first);
    } catch (e) {
      return null;
    }
  }

  /// 当前位置之后的下一个 POI（用于导航式「下一站 · 还有 x.x km」）
  /// 查 river_pois 中 distance_km > accumulatedKm 的第一条，按 distance_km 升序。
  Future<RiverPoi?> getNextPoi(int numericId, double accumulatedKm) async {
    try {
      final db = await instance.baseDatabase;
      if (db == null) return null;
      final rows = await db.query(
        'river_pois',
        where: 'numeric_id = ? AND distance_km > ?',
        whereArgs: [numericId, accumulatedKm],
        orderBy: 'distance_km ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return RiverPoi.fromMap(rows.first);
    } catch (e) {
      return null;
    }
  }

  /// 下一站（路线上的下一处「不同地址」路径点）：只取 formatted_address 与当前位置不同的下一个点。
  /// 这样展示的是「下一段路的目的地」，而不是同一条路名下的多条 POI 记录，更符合导航语义。
  /// [currentFormattedAddress] 为当前最近点的 formatted_address（如 null 则等价于 getNextPoi）。
  Future<RiverPoi?> getNextPoiWithDistinctAddress(
    int numericId,
    double accumulatedKm,
    String? currentFormattedAddress,
  ) async {
    try {
      final db = await instance.baseDatabase;
      if (db == null) return null;
      final trimmed = currentFormattedAddress?.trim();
      final bool filterByAddress = trimmed != null && trimmed.isNotEmpty;

      final List<Map<String, dynamic>> rows;
      if (filterByAddress) {
        rows = await db.query(
          'river_pois',
          where:
              "numeric_id = ? AND distance_km > ? AND (formatted_address IS NULL OR trim(COALESCE(formatted_address, '')) != ?)",
          whereArgs: [numericId, accumulatedKm, trimmed],
          orderBy: 'distance_km ASC',
          limit: 1,
        );
      } else {
        rows = await db.query(
          'river_pois',
          where: 'numeric_id = ? AND distance_km > ?',
          whereArgs: [numericId, accumulatedKm],
          orderBy: 'distance_km ASC',
          limit: 1,
        );
      }
      if (rows.isEmpty) return null;
      return RiverPoi.fromMap(rows.first);
    } catch (e) {
      return null;
    }
  }
}
