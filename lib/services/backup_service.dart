// 涉川数据备份与恢复：主库表、SharedPreferences、用户头像打包为单文件，支持换机导入。
// 设计：版本化 manifest、类型化 prefs 导出、表数据 JSON 序列化、二进制附件（头像），ZIP 单文件便于分享与校验。

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

import 'database_service.dart';
import '../models/daily_stats.dart';

const int kBackupSchemaVersion = 1;
const String kBackupFileExtension = 'rivtrek';

/// 需要备份的 SharedPreferences 键及其类型（s=String, i=int, b=bool, d=double, l=List<String>）
const Map<String, String> _prefsKeys = {
  'has_completed_initial_river_selection': 'b',
  'sensor_permission_hint_disabled': 'b',
  'last_steps_source': 's',
  'active_river_id': 's',
  'cached_weather_v2': 's',
  'challenge_start_date': 's',
  'sensor_last_sync_date': 's',
  'sensor_last_day_end_cumulative': 'i',
  'sensor_steps_at_day_start': 'i',
  'user_nickname': 's',
  'user_signature': 's',
  'user_avatar_path': 's',
  'river_path_mode': 'i',
  'river_style': 'i',
  'river_speed': 'd',
  'river_turbulence': 'd',
  'river_width': 'd',
  'Favorites': 'l',
};

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  /// 生成备份并返回本地文件路径，便于分享或保存。
  /// 包含：manifest、prefs、主库三张表导出、用户头像（若有）。
  Future<String> createBackup() async {
    final dir = await getTemporaryDirectory();
    final name = 'rivtrek_backup_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.$kBackupFileExtension';
    final path = p.join(dir.path, name);

    final archive = Archive();

    // 1. manifest
    final manifest = {
      'version': kBackupSchemaVersion,
      'created_at': DateTime.now().toIso8601String(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 2. prefs（按类型导出，恢复时按类型写回）
    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final entry in _prefsKeys.entries) {
      final key = entry.key;
      final type = entry.value;
      Object? v;
      switch (type) {
        case 's':
          v = prefs.getString(key);
          break;
        case 'i':
          v = prefs.getInt(key);
          break;
        case 'b':
          v = prefs.getBool(key);
          break;
        case 'd':
          v = prefs.getDouble(key);
          break;
        case 'l':
          v = prefs.getStringList(key);
          break;
      }
      if (v != null) prefsMap[key] = v;
    }
    final prefsBytes = utf8.encode(jsonEncode(prefsMap));
    archive.addFile(ArchiveFile('prefs.json', prefsBytes.length, prefsBytes));

    // 3. 主库表导出（不关库，只读导出）
    final activities = await DatabaseService.instance.getAllActivities();
    final weather = await DatabaseService.instance.getAllWeather();
    final events = await DatabaseService.instance.getAllEvents();
    final activitiesBytes = utf8.encode(jsonEncode(activities.map((a) => a.toMap()).toList()));
    final weatherBytes = utf8.encode(jsonEncode(weather.map((w) => w.toMap()).toList()));
    final eventsBytes = utf8.encode(jsonEncode(events.map((e) => e.toMap()).toList()));
    archive.addFile(ArchiveFile('data/activities.json', activitiesBytes.length, activitiesBytes));
    archive.addFile(ArchiveFile('data/weather.json', weatherBytes.length, weatherBytes));
    archive.addFile(ArchiveFile('data/events.json', eventsBytes.length, eventsBytes));

    // 4. 用户头像（若有）：备份文件内容，恢复时写到新设备应用目录并更新 prefs 中的路径
    final avatarPath = prefs.getString('user_avatar_path');
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final f = File(avatarPath);
      if (f.existsSync()) {
        final avatarBytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile('user/avatar.jpg', avatarBytes.length, avatarBytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    final out = File(path);
    await out.writeAsBytes(zipData);
    return path;
  }

  /// 将已生成的备份文件复制到本机「下载」目录（应用专属目录，无需存储权限），返回目标路径；失败返回 null。
  Future<String?> saveBackupToDownloads(String backupFilePath) async {
    final src = File(backupFilePath);
    if (!src.existsSync()) return null;
    final dir = await getDownloadsDirectory();
    if (dir == null) return null;
    final name = p.basename(backupFilePath);
    final dest = File(p.join(dir.path, name));
    await src.copy(dest.path);
    return dest.path;
  }

  /// 从备份文件恢复。会覆盖当前主库表、prefs 中备份过的键、用户头像。
  /// 恢复后调用方应让 ChallengeProvider / UserProfileProvider / FlowController 重新加载（如 switchRiver、load、refreshFromDb）。
  Future<void> restoreBackup(String backupFilePath) async {
    final file = File(backupFilePath);
    if (!file.existsSync()) throw ArgumentError('Backup file not found: $backupFilePath');
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.isEmpty) throw ArgumentError('Invalid backup: empty archive');

    ArchiveFile? manifestFile;
    ArchiveFile? prefsFile;
    ArchiveFile? activitiesFile;
    ArchiveFile? weatherFile;
    ArchiveFile? eventsFile;
    ArchiveFile? avatarFile;
    for (final f in archive.files) {
      if (f.name == 'manifest.json') manifestFile = f;
      else if (f.name == 'prefs.json') prefsFile = f;
      else if (f.name == 'data/activities.json') activitiesFile = f;
      else if (f.name == 'data/weather.json') weatherFile = f;
      else if (f.name == 'data/events.json') eventsFile = f;
      else if (f.name == 'user/avatar.jpg') avatarFile = f;
    }
    if (manifestFile == null || prefsFile == null) throw ArgumentError('Invalid backup: missing manifest or prefs');

    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    final version = manifest['version'] as int? ?? 0;
    if (version > kBackupSchemaVersion) {
      throw ArgumentError('Backup was created by a newer app version. Please update 涉川.');
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = jsonDecode(utf8.decode(prefsFile.content)) as Map<String, dynamic>;
    for (final entry in prefsMap.entries) {
      final key = entry.key;
      final type = _prefsKeys[key];
      if (type == null) continue;
      final v = entry.value;
      switch (type) {
        case 's':
          if (v is String) await prefs.setString(key, v);
          break;
        case 'i':
          if (v is int) await prefs.setInt(key, v);
          break;
        case 'b':
          if (v is bool) await prefs.setBool(key, v);
          break;
        case 'd':
          if (v is num) await prefs.setDouble(key, v.toDouble());
          break;
        case 'l':
          if (v is List) await prefs.setStringList(key, v.map((e) => e.toString()).toList());
          break;
      }
    }

    // 恢复头像到应用目录，并覆盖 prefs 中的路径（新设备路径不同）
    if (avatarFile != null && avatarFile.content.isNotEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      const name = 'avatar.jpg';
      final dest = File(p.join(dir.path, name));
      await dest.writeAsBytes(avatarFile.content);
      await prefs.setString('user_avatar_path', dest.path);
    } else {
      await prefs.remove('user_avatar_path');
    }

    // 恢复主库：清空后按备份逐条插入
    final db = await DatabaseService.instance.database;
    await db.delete('daily_activities');
    await db.delete('daily_weather');
    await db.delete('river_events');

    if (activitiesFile != null && activitiesFile.content.isNotEmpty) {
      final list = jsonDecode(utf8.decode(activitiesFile.content)) as List<dynamic>;
      for (final m in list) {
        final a = DailyActivity.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.instance.saveActivity(a);
      }
    }
    if (weatherFile != null && weatherFile.content.isNotEmpty) {
      final list = jsonDecode(utf8.decode(weatherFile.content)) as List<dynamic>;
      for (final m in list) {
        final w = DailyWeather.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.instance.saveWeather(w);
      }
    }
    if (eventsFile != null && eventsFile.content.isNotEmpty) {
      final list = jsonDecode(utf8.decode(eventsFile.content)) as List<dynamic>;
      for (final m in list) {
        final map = Map<String, dynamic>.from(m as Map);
        final e = RiverEvent(
          id: map['id'] is int ? map['id'] as int : null,
          date: map['date'] as String,
          timestamp: (map['timestamp'] as num).toInt(),
          type: RiverEventType.values.firstWhere(
            (x) => x.name == map['type'],
            orElse: () => RiverEventType.activity,
          ),
          name: map['name'] as String,
          description: map['description'] as String,
          latitude: (map['latitude'] as num).toDouble(),
          longitude: (map['longitude'] as num).toDouble(),
          distanceAtKm: (map['distance_at_km'] as num).toDouble(),
          extraData: map['extra_data'] as String? ?? '{}',
        );
        await DatabaseService.instance.recordEvent(e);
      }
    }
  }
}
