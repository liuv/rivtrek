import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_stats.dart';

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
      version: 3, 
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE daily_weather ADD COLUMN aqi TEXT DEFAULT "--"');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE daily_activities ADD COLUMN river_id TEXT DEFAULT "yangtze"');
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
}
