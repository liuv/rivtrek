import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:app_settings/app_settings.dart';
import '../models/river_settings.dart';
import '../services/backup_service.dart';
import '../providers/challenge_provider.dart';
import '../providers/user_profile_provider.dart';
import '../controllers/flow_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool? _batteryOptDisabled;
  bool? _autoStartEnabled;
  bool _permissionLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) _loadPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _loadPermissionStatus();
    }
  }

  Future<void> _loadPermissionStatus() async {
    if (!Platform.isAndroid) return;
    setState(() => _permissionLoading = true);
    try {
      final battery = await DisableBatteryOptimization.isBatteryOptimizationDisabled;
      final auto = await DisableBatteryOptimization.isAutoStartEnabled;
      if (mounted) setState(() {
        _batteryOptDisabled = battery;
        _autoStartEnabled = auto;
        _permissionLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _permissionLoading = false);
    }
  }

  Future<void> _loadInitialSettings() async {
    final prefs = await SharedPreferences.getInstance();
    RiverSettings.instance.update(
      pathMode: RiverPathMode.values[prefs.getInt('river_path_mode') ?? 0],
      style: RiverStyle.values[prefs.getInt('river_style') ?? 0],
      speed: prefs.getDouble('river_speed') ?? 0.3,
      turbulence: prefs.getDouble('river_turbulence') ?? 0.6,
      width: prefs.getDouble('river_width') ?? 0.18,
    );
  }

  Future<void> _saveSettings({
    RiverPathMode? pathMode,
    RiverStyle? style,
    double? speed,
    double? turbulence,
    double? width,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (pathMode != null) await prefs.setInt('river_path_mode', pathMode.index);
    if (style != null) await prefs.setInt('river_style', style.index);
    if (speed != null) await prefs.setDouble('river_speed', speed);
    if (turbulence != null) await prefs.setDouble('river_turbulence', turbulence);
    if (width != null) await prefs.setDouble('river_width', width);
    
    RiverSettings.instance.update(
      pathMode: pathMode,
      style: style,
      speed: speed,
      turbulence: turbulence,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用设置', style: TextStyle(fontWeight: FontWeight.w300)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListenableBuilder(
        listenable: RiverSettings.instance,
        builder: (context, _) {
          final settings = RiverSettings.instance;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSectionTitle('权限设置'),
              if (Platform.isAndroid) _buildBackendStepsSection(context),
              if (Platform.isAndroid) const SizedBox(height: 32),
              _buildSectionTitle('效果设置'),
              _buildSectionTitle('河道路径模式'),
              Card(
                elevation: 0,
                color: Colors.grey[100],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildPathModeTile(RiverPathMode.procedural, '程序化模拟', '算法生成的数学曲线'),
                    _buildPathModeTile(RiverPathMode.realPath, '真实路径', '基于地理数据的真实弯折'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('视觉表现风格'),
              Card(
                elevation: 0,
                color: Colors.grey[100],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildStyleTile(RiverStyle.classic, '经典流体', '默认的丝绸质感渲染'),
                    _buildStyleTile(RiverStyle.ink, '水墨意境', '复古的水墨晕染效果'),
                    _buildStyleTile(RiverStyle.aurora, '极光之径', '绚丽的动态极光效果'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('参数微调'),
              const SizedBox(height: 16),
              _buildSlider('流动速度', settings.speed, 0.1, 1.0, (val) {
                _saveSettings(speed: val);
              }),
              _buildSlider('湍流强度', settings.turbulence, 0.1, 2.0, (val) {
                _saveSettings(turbulence: val);
              }),
              _buildSlider('河道宽度', settings.width, 0.05, 0.4, (val) {
                _saveSettings(width: val);
              }),
              const SizedBox(height: 32),
              _buildSectionTitle('数据与备份'),
              Card(
                elevation: 0,
                color: Colors.grey[100],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_outlined, size: 22),
                      title: const Text('导出备份'),
                      subtitle: const Text('将步数、天气、事件与个人资料打包为单文件，可分享保存或换机导入'),
                      onTap: _onExportBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore_outlined, size: 22),
                      title: const Text('从备份恢复'),
                      subtitle: const Text('选择此前导出的 .rivtrek 文件，覆盖当前数据（建议先备份当前数据）'),
                      onTap: _onRestoreBackup,
                    ),
                  ],
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _onExportBackup() async {
    try {
      final path = await BackupService.instance.createBackup();
      if (!mounted) return;
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('分享或发送'),
                subtitle: const Text('通过微信、邮件等分享到云盘或新设备'),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存到手机'),
                subtitle: const Text('保存到本机「下载」目录，便于稍后拷贝到电脑或新机'),
                onTap: () => Navigator.of(ctx).pop('save'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == 'share') {
        await Share.shareXFiles(
          [XFile(path)],
          subject: '涉川数据备份',
          text: '涉川数据备份，可在新设备上通过「设置 → 从备份恢复」导入。',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请通过分享保存到云盘或发送到新设备'), duration: Duration(seconds: 3)),
          );
        }
      } else if (choice == 'save') {
        final savedPath = await BackupService.instance.saveBackupToDownloads(path);
        if (mounted && savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存到：$savedPath'), duration: const Duration(seconds: 4)),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取下载目录，请使用「分享」保存'), duration: Duration(seconds: 3)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e'), duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  Future<void> _onRestoreBackup() async {
    // Android 上自定义扩展名 rivtrek 不被系统识别会报错，故用 FileType.any，选完后校验扩展名
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法读取所选文件路径，请从「文件」或「下载」中选择 .rivtrek 文件'), duration: Duration(seconds: 3)),
        );
      }
      return;
    }
    final name = file.name.toLowerCase();
    if (!name.endsWith('.$kBackupFileExtension')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择 .rivtrek 备份文件'), duration: Duration(seconds: 3)),
        );
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text(
          '将从所选备份覆盖当前设备上的活动、天气、事件与个人设置。此操作不可撤销，建议先导出当前数据再恢复。是否继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('恢复')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await BackupService.instance.restoreBackup(path);
      final prefs = await SharedPreferences.getInstance();
      final activeRiverId = prefs.getString('active_river_id') ?? 'yangtze';
      if (mounted) {
        await context.read<ChallengeProvider>().switchRiver(activeRiverId);
        await context.read<UserProfileProvider>().reloadFromPrefs();
        await context.read<FlowController>().refreshFromDb();
      }
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('恢复完成'),
            content: const Text('数据已恢复。建议重启应用以使时间线收藏等全部生效。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据已恢复，建议重启应用'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$e'), duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  Widget _buildBackendStepsSection(BuildContext context) {
    final grantedColor = const Color(0xFF2E7D32);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('步数记录'),
        Card(
          elevation: 0,
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '在未打开 App 时，涉川也会在后台为您记录步数。若发现某天步数为 0 或明显偏少，'
                  '建议在下方开启相应权限，以便系统允许后台记录。',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                _buildPermissionTile(
                  context,
                  icon: Icons.battery_charging_full,
                  title: '忽略电池优化',
                  granted: _batteryOptDisabled == true,
                  loading: _permissionLoading,
                  onTap: () async {
                    try {
                      await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
                    } catch (_) {
                      if (context.mounted) {
                        await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
                      }
                    }
                  },
                  grantedColor: grantedColor,
                ),
                const Divider(height: 1),
                _buildPermissionTile(
                  context,
                  icon: Icons.rocket_launch_outlined,
                  title: '自启动（小米等）',
                  granted: _autoStartEnabled == true,
                  loading: _permissionLoading,
                  onTap: () async {
                    try {
                      await DisableBatteryOptimization.showEnableAutoStartSettings(
                        '开启自启动',
                        '请按步骤允许涉川自启动，以便在未打开 App 时也能记录步数。',
                      );
                    } catch (_) {
                      if (context.mounted) {
                        await AppSettings.openAppSettings(type: AppSettingsType.settings);
                      }
                    }
                  },
                  grantedColor: grantedColor,
                ),
                const SizedBox(height: 16),
                Text(
                  '若您曾选择「不再提示」，可在此重新开启进入时的权限提醒。',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('sensor_permission_hint_disabled', false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已开启，下次进入 App 时会再次提醒权限'), duration: Duration(seconds: 2)),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('下次进入时再次提醒'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool granted,
    required bool loading,
    required VoidCallback onTap,
    required Color grantedColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 22, color: granted ? grantedColor : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: granted ? FontWeight.w600 : FontWeight.w400,
          color: granted ? grantedColor : Colors.black87,
        ),
      ),
      trailing: loading
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              granted ? Icons.check_circle : Icons.check_circle_outline,
              color: granted ? grantedColor : Colors.grey.shade400,
              size: 22,
            ),
      onTap: onTap,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildPathModeTile(RiverPathMode mode, String title, String subtitle) {
    bool selected = RiverSettings.instance.pathMode == mode;
    return ListTile(
      title: Text(title, style: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? Colors.blue[800] : Colors.black87,
      )),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: selected ? Icon(Icons.check_circle, color: Colors.blue[800]) : null,
      onTap: () => _saveSettings(pathMode: mode),
    );
  }

  Widget _buildStyleTile(RiverStyle style, String title, String subtitle) {
    bool selected = RiverSettings.instance.style == style;
    return ListTile(
      title: Text(title, style: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? Colors.blue[800] : Colors.black87,
      )),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: selected ? Icon(Icons.check_circle, color: Colors.blue[800]) : null,
      onTap: () => _saveSettings(style: style),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Text(value.toStringAsFixed(2), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          activeColor: Colors.blue[800],
          inactiveColor: Colors.blue[100],
        ),
      ],
    );
  }
}
