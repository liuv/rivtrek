// 涉川数据备份与恢复：主库表、SharedPreferences、用户头像打包为单文件，支持换机导入。
// 设计：版本化 manifest、类型化 prefs 导出、表数据 JSON 序列化、二进制附件（头像），ZIP 单文件便于分享与校验。
// v2: 核心数据（步数、里程、事件、敏感 prefs）使用 AES-256-GCM 加密，防止篡改伪造徒步数据；头像与展示类 prefs 保持明文。

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import '../models/daily_stats.dart';

const int kBackupSchemaVersion = 2;
const String kBackupFileExtension = 'rivtrek';

/// 应用内嵌密钥，用于派生加密密钥。生产环境可通过 build-time 注入替换。
/// 即使开源可见，仍能有效阻止普通用户直接修改 JSON 伪造数据（需逆向+重加密）。
const String _kBackupAppSecret = 'rivtrek-backup-aes256-v2-7f3e9a2b';

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
  'drift_cross_screen_seconds': 'd',
  'Favorites': 'l',
};

/// 敏感 prefs 键（影响挑战进度，需加密防篡改）
const Set<String> _sensitivePrefsKeys = {
  'challenge_start_date',
};

/// 设备相关 prefs 键：与当前设备硬件绑定，换机/重装后无效，不备份不恢复。
/// 恢复后步数同步会走「首次安装」逻辑，以当前传感器为基线重新计算今日步数。
const Set<String> _deviceSpecificPrefsKeys = {
  'sensor_last_sync_date',
  'sensor_last_day_end_cumulative',
  'sensor_steps_at_day_start',
};

/// 恢复后首次传感器同步时使用的「今日已走步数」偏移。由 BackupService 在恢复时注入，
/// StepSyncService 首次同步时消费并清除。用于解决：恢复后传感器基线清空，但 DB 已有今日步数，
/// 导致 max(sensor_today, db_today) 长期取 db 值、步数无法累加的问题。
const String kSensorRestoredTodaySteps = 'sensor_restored_today_steps';

/// 恢复进行中标记。恢复期间 StepSyncService 跳过同步，避免与 WorkManager 竞态。
const String kRestoreInProgress = 'backup_restore_in_progress';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  static final _aesGcm = AesGcm.with256bits();
  static final _sha256 = Sha256();
  static final _random = Random.secure();

  /// 从 app secret + salt 派生 AES-256 密钥
  Future<SecretKey> _deriveKey(List<int> salt) async {
    final combined = utf8.encode(_kBackupAppSecret) + salt;
    final hash = await _sha256.hash(combined);
    return SecretKey(hash.bytes);
  }

  /// 加密 JSON 字符串，返回二进制（nonce + ciphertext + mac）
  Future<List<int>> _encrypt(String plainJson, SecretKey key) async {
    final plainBytes = utf8.encode(plainJson);
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: key,
    );
    return secretBox.concatenation();
  }

  /// 解密二进制为 JSON 字符串
  Future<String> _decrypt(List<int> encryptedBytes, SecretKey key) async {
    final secretBox = SecretBox.fromConcatenation(
      encryptedBytes,
      nonceLength: _aesGcm.nonceLength,
      macLength: _aesGcm.macAlgorithm.macLength,
    );
    final decrypted = await _aesGcm.decrypt(
      secretBox,
      secretKey: key,
    );
    return utf8.decode(decrypted);
  }

  /// 生成 16 字节随机 salt
  List<int> _randomSalt() => List<int>.generate(16, (_) => _random.nextInt(256));

  /// 生成备份并返回本地文件路径，便于分享或保存。
  /// v2: 核心数据加密，头像与展示类 prefs 明文。
  Future<String> createBackup() async {
    final dir = await getTemporaryDirectory();
    final name = 'rivtrek_backup_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.$kBackupFileExtension';
    final path = p.join(dir.path, name);

    final salt = _randomSalt();
    final key = await _deriveKey(salt);

    final archive = Archive();

    // 1. manifest（含 salt，用于派生密钥）
    final manifest = {
      'version': kBackupSchemaVersion,
      'created_at': DateTime.now().toIso8601String(),
      'encrypted': true,
      'salt': base64Encode(salt),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 2. prefs：拆分为明文（展示类）与加密（敏感）
    final prefs = await SharedPreferences.getInstance();
    final prefsPlain = <String, dynamic>{};
    final prefsSensitive = <String, dynamic>{};
    for (final entry in _prefsKeys.entries) {
      final keyName = entry.key;
      final type = entry.value;
      Object? v;
      switch (type) {
        case 's':
          v = prefs.getString(keyName);
          break;
        case 'i':
          v = prefs.getInt(keyName);
          break;
        case 'b':
          v = prefs.getBool(keyName);
          break;
        case 'd':
          v = prefs.getDouble(keyName);
          break;
        case 'l':
          v = prefs.getStringList(keyName);
          break;
      }
      if (v != null && !_deviceSpecificPrefsKeys.contains(keyName)) {
        if (_sensitivePrefsKeys.contains(keyName)) {
          prefsSensitive[keyName] = v;
        } else {
          prefsPlain[keyName] = v;
        }
      }
    }
    final prefsPlainBytes = utf8.encode(jsonEncode(prefsPlain));
    archive.addFile(ArchiveFile('prefs.json', prefsPlainBytes.length, prefsPlainBytes));

    final prefsSensitiveJson = jsonEncode(prefsSensitive);
    final prefsSensitiveEnc = await _encrypt(prefsSensitiveJson, key);
    archive.addFile(ArchiveFile('prefs_sensitive.enc', prefsSensitiveEnc.length, prefsSensitiveEnc));

    // 3. 主库表导出（加密）
    final activities = await DatabaseService.instance.getAllActivities();
    final weather = await DatabaseService.instance.getAllWeather();
    final events = await DatabaseService.instance.getAllEvents();
    final activitiesJson = jsonEncode(activities.map((a) => a.toMap()).toList());
    final weatherJson = jsonEncode(weather.map((w) => w.toMap()).toList());
    final eventsJson = jsonEncode(events.map((e) => e.toMap()).toList());

    final activitiesEnc = await _encrypt(activitiesJson, key);
    final weatherEnc = await _encrypt(weatherJson, key);
    final eventsEnc = await _encrypt(eventsJson, key);

    archive.addFile(ArchiveFile('data/activities.enc', activitiesEnc.length, activitiesEnc));
    archive.addFile(ArchiveFile('data/weather.enc', weatherEnc.length, weatherEnc));
    archive.addFile(ArchiveFile('data/events.enc', eventsEnc.length, eventsEnc));

    // 4. 用户头像（明文，不加密）
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

  /// 从备份文件恢复。会覆盖当前主库表、prefs 中备份过的键、用户头像。
  /// 仅支持 v2 加密备份格式。
  Future<void> restoreBackup(String backupFilePath) async {
    final file = File(backupFilePath);
    if (!file.existsSync()) throw ArgumentError('Backup file not found: $backupFilePath');
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.isEmpty) throw ArgumentError('Invalid backup: empty archive');

    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      files[f.name] = f;
    }

    // 拒绝 v1 明文格式：明文备份可被篡改，存在伪造风险。仅支持 v2 加密备份。
    if (files.containsKey('data/activities.json') ||
        files.containsKey('data/weather.json') ||
        files.containsKey('data/events.json')) {
      throw ArgumentError('此备份为早期明文格式，已不再支持恢复。请使用最新版本创建加密备份。');
    }

    final manifestFile = files['manifest.json'];
    final prefsFile = files['prefs.json'];
    if (manifestFile == null || prefsFile == null) {
      throw ArgumentError('Invalid backup: missing manifest or prefs');
    }

    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    final version = manifest['version'] as int? ?? 0;
    if (version > kBackupSchemaVersion) {
      throw ArgumentError('Backup was created by a newer app version. Please update 涉川.');
    }
    final encrypted = manifest['encrypted'] as bool? ?? false;
    if (!encrypted || version < 2) {
      throw ArgumentError('此备份为早期明文格式，已不再支持恢复。请使用最新版本创建加密备份。');
    }

    final saltB64 = manifest['salt'] as String?;
    if (saltB64 == null || saltB64.isEmpty) {
      throw ArgumentError('Invalid encrypted backup: missing salt');
    }
    final key = await _deriveKey(base64Decode(saltB64));

    final prefs = await SharedPreferences.getInstance();

    // 恢复明文 prefs
    final prefsMap = jsonDecode(utf8.decode(prefsFile.content)) as Map<String, dynamic>;
    await _applyPrefsMap(prefs, prefsMap);

    // 恢复加密的敏感 prefs
    final prefsSensitiveFile = files['prefs_sensitive.enc'];
    if (prefsSensitiveFile != null && prefsSensitiveFile.content.isNotEmpty) {
      final decrypted = await _decrypt(prefsSensitiveFile.content, key);
      final sensitiveMap = jsonDecode(decrypted) as Map<String, dynamic>;
      await _applyPrefsMap(prefs, sensitiveMap);
    }

    // 清除设备相关 sensor 基线：换机/重装后旧设备的累计值无效，步数同步会以当前传感器为基线重新计算今日步数
    for (final k in _deviceSpecificPrefsKeys) {
      await prefs.remove(k);
    }

    // 恢复头像
    final avatarFile = files['user/avatar.jpg'];
    if (avatarFile != null && avatarFile.content.isNotEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      const name = 'avatar.jpg';
      final dest = File(p.join(dir.path, name));
      await dest.writeAsBytes(avatarFile.content);
      await prefs.setString('user_avatar_path', dest.path);
    } else {
      await prefs.remove('user_avatar_path');
    }

    // 恢复主库（事务保证原子性：要么全部成功，要么全部回滚）
    final activitiesEnc = files['data/activities.enc'];
    final weatherEnc = files['data/weather.enc'];
    final eventsEnc = files['data/events.enc'];

    await prefs.setBool(kRestoreInProgress, true);
    try {
      final db = await DatabaseService.instance.database;
      await db.transaction((txn) async {
        await txn.delete('daily_activities');
        await txn.delete('daily_weather');
        await txn.delete('river_events');

        if (activitiesEnc != null && activitiesEnc.content.isNotEmpty) {
          final jsonStr = await _decrypt(activitiesEnc.content, key);
          final list = jsonDecode(jsonStr) as List<dynamic>;
          for (final m in list) {
            final a = DailyActivity.fromMap(Map<String, dynamic>.from(m as Map));
            await txn.insert('daily_activities', a.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        if (weatherEnc != null && weatherEnc.content.isNotEmpty) {
          final jsonStr = await _decrypt(weatherEnc.content, key);
          final list = jsonDecode(jsonStr) as List<dynamic>;
          for (final m in list) {
            final w = DailyWeather.fromMap(Map<String, dynamic>.from(m as Map));
            await txn.insert('daily_weather', w.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        if (eventsEnc != null && eventsEnc.content.isNotEmpty) {
          final jsonStr = await _decrypt(eventsEnc.content, key);
          final list = jsonDecode(jsonStr) as List<dynamic>;
          for (final m in list) {
            final map = Map<String, dynamic>.from(m as Map);
            await txn.insert('river_events', {
              'date': map['date'] as String,
              'timestamp': (map['timestamp'] as num).toInt(),
              'type': map['type'] as String,
              'name': map['name'] as String,
              'description': map['description'] as String,
              'latitude': (map['latitude'] as num).toDouble(),
              'longitude': (map['longitude'] as num).toDouble(),
              'distance_at_km': (map['distance_at_km'] as num).toDouble(),
              'extra_data': map['extra_data'] as String? ?? '{}',
            });
          }
        }
      });

      // 注入今日步数偏移（事务成功后）
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final activeRiverId = prefs.getString('active_river_id') ?? 'yangtze';
      if (activitiesEnc != null && activitiesEnc.content.isNotEmpty) {
        final jsonStr = await _decrypt(activitiesEnc.content, key);
        final list = jsonDecode(jsonStr) as List<dynamic>;
        int? restoredTodaySteps;
        for (final m in list) {
          final a = DailyActivity.fromMap(Map<String, dynamic>.from(m as Map));
          if (a.date == todayStr && a.riverId == activeRiverId) {
            restoredTodaySteps = a.steps;
            break;
          }
        }
        if (restoredTodaySteps != null && restoredTodaySteps > 0) {
          await prefs.setInt(kSensorRestoredTodaySteps, restoredTodaySteps);
        }
      }
    } finally {
      await prefs.remove(kRestoreInProgress);
    }
  }

  Future<void> _applyPrefsMap(SharedPreferences prefs, Map<String, dynamic> prefsMap) async {
    for (final entry in prefsMap.entries) {
      final key = entry.key;
      if (_deviceSpecificPrefsKeys.contains(key)) continue;
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
  }
}
