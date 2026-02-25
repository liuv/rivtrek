import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:app_settings/app_settings.dart';
import '../models/river_settings.dart';
import '../providers/theme_provider.dart';
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
    await RiverSettings.loadFromPrefs();
  }

  Future<void> _saveSettings({
    RiverPathMode? pathMode,
    RiverStyle? style,
    double? speed,
    double? turbulence,
    double? width,
    double? driftCrossScreenSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (pathMode != null) await prefs.setInt('river_path_mode', pathMode.index);
    if (style != null) await prefs.setInt('river_style', style.index);
    if (speed != null) await prefs.setDouble('river_speed', speed);
    if (turbulence != null) await prefs.setDouble('river_turbulence', turbulence);
    if (width != null) await prefs.setDouble('river_width', width);
    if (driftCrossScreenSeconds != null) {
      await prefs.setDouble(
          'drift_cross_screen_seconds',
          driftCrossScreenSeconds.clamp(
              kDriftCrossScreenMinSeconds, kDriftCrossScreenMaxSeconds));
    }

    RiverSettings.instance.update(
      pathMode: pathMode,
      style: style,
      speed: speed,
      turbulence: turbulence,
      width: width,
      driftCrossScreenSeconds: driftCrossScreenSeconds,
    );
  }

  /// 过屏时间（秒）转成用户看到的「漂浮速度倍数」：60 秒 = 1x，30 秒 = 2x，120 秒 = 0.5x
  static double _secondsToMultiplier(double seconds) {
    if (seconds <= 0) return 2;
    return 60 / seconds;
  }

  static String _formatDriftMultiplier(double multiplier) {
    if (multiplier >= 1) {
      if (multiplier == multiplier.roundToDouble()) return '${multiplier.round()}x';
      return '${multiplier.toStringAsFixed(1)}x';
    }
    if (multiplier < 0.1) return '${multiplier.toStringAsFixed(2)}x';
    return '${multiplier.toStringAsFixed(1)}x';
  }

  static const List<Color> _seedColorPresets = [
    Color(0xFF0097A7), // 青 (原默认)
    Color(0xFF1976D2), // 蓝
    Color(0xFF7B1FA2), // 紫
    Color(0xFFC2185B), // 粉
    Color(0xFFE64A19), // 橙
    Color(0xFF388E3C), // 绿
    Color(0xFF00796B), //  Teal
    Color(0xFF5D4037), // 棕
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用设置', style: TextStyle(fontWeight: FontWeight.w300)),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListenableBuilder(
        listenable: RiverSettings.instance,
        builder: (context, _) {
          final settings = RiverSettings.instance;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSectionTitle(context, '外观'),
              ListenableBuilder(
                listenable: ThemeProvider.instance,
                builder: (context, _) {
                  final theme = ThemeProvider.instance;
                  return Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('深色模式'),
                          subtitle: const Text('切换亮色 / 暗色主题'),
                          value: theme.isDark,
                          onChanged: (v) => theme.setBrightness(v ? Brightness.dark : Brightness.light),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              Text('主题色', style: TextStyle(fontSize: 16, color: colorScheme.onSurface)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: _seedColorPresets.map((c) {
                                    final selected = theme.seedColor == c;
                                    return Material(
                                      color: selected ? c : c.withOpacity(0.35),
                                      borderRadius: BorderRadius.circular(20),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => theme.setSeedColor(c),
                                        child: SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: selected
                                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                                              : null,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          title: const Text('河流颜色跟随主题'),
                          subtitle: const Text('开启后首页河流效果使用当前主题色，关闭则按河段数据配色'),
                          value: theme.useThemeColorForRiver,
                          onChanged: (v) => theme.setUseThemeColorForRiver(v),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              _buildSectionTitle(context, '权限设置'),
              if (Platform.isAndroid) _buildBackendStepsSection(context),
              if (Platform.isAndroid) const SizedBox(height: 32),
              _buildSectionTitle(context, '效果设置'),
              _buildSectionTitle(context, '河道路径模式'),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildPathModeTile(context, RiverPathMode.procedural, '程序化模拟', '算法生成的数学曲线'),
                    _buildPathModeTile(context, RiverPathMode.realPath, '真实路径', '基于地理数据的真实弯折'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionTitle(context, '视觉表现风格'),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildStyleTile(context, RiverStyle.classic, '经典流体', '默认的丝绸质感渲染'),
                    _buildStyleTile(context, RiverStyle.ink, '水墨意境', '复古的水墨晕染效果'),
                    _buildStyleTile(context, RiverStyle.aurora, '极光之径', '绚丽的动态极光效果'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionTitle(context, '参数微调'),
              const SizedBox(height: 16),
              _buildSlider(context, '流动速度', settings.speed, 0.1, 1.0, (val) {
                _saveSettings(speed: val);
              }),
              _buildSlider(context, '湍流强度', settings.turbulence, 0.1, 2.0, (val) {
                _saveSettings(turbulence: val);
              }),
              _buildSlider(context, '河道宽度', settings.width, 0.05, 0.4, (val) {
                _saveSettings(width: val);
              }),
              const SizedBox(height: 24),
              _buildSectionTitle(context, '河灯 / 漂流瓶'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '漂浮速度倍数，左慢右快。参考：1x 为一屏 3 公里 60 秒漂过，约合每公里 20 秒的观感；各河段仍按流速有快慢差异。',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.35),
                ),
              ),
              const SizedBox(height: 8),
              _buildDriftSpeedMultiplierSlider(context, settings.driftCrossScreenSeconds),
              const SizedBox(height: 32),
              _buildSectionTitle(context, '数据与备份'),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.backup_outlined, size: 22, color: colorScheme.primary),
                      title: Text('导出备份', style: TextStyle(color: colorScheme.onSurface)),
                      subtitle: Text('将步数、天气、事件与个人资料打包为单文件，可分享保存或换机导入', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      onTap: _onExportBackup,
                    ),
                    Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.2)),
                    ListTile(
                      leading: Icon(Icons.restore_outlined, size: 22, color: colorScheme.primary),
                      title: Text('从备份恢复', style: TextStyle(color: colorScheme.onSurface)),
                      subtitle: Text('选择此前导出的 .rivtrek 文件，覆盖当前数据（建议先备份当前数据）', style: TextStyle(color: colorScheme.onSurfaceVariant)),
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
                subtitle: Text(Platform.isIOS
                    ? '通过分享可保存到相册/文件或发送到其他设备'
                    : '通过微信、邮件等分享到云盘或新设备'),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
              if (!Platform.isIOS)
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
        await ThemeProvider.loadFromPrefs();
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
    final cs = Theme.of(context).colorScheme;
    final grantedColor = cs.primary; // 已开启用主题主色，或保持绿色：Color(0xFF2E7D32)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, '步数记录'),
        Card(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '在未打开 App 时，涉川也会在后台为您记录步数。若发现某天步数为 0 或明显偏少，'
                  '建议在下方开启相应权限，以便系统允许后台记录。',
                  style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurface),
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
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.3),
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
                  icon: Icon(Icons.notifications_active_outlined, size: 18, color: cs.primary),
                  label: Text('下次进入时再次提醒', style: TextStyle(color: cs.primary)),
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
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 22, color: granted ? grantedColor : cs.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: granted ? FontWeight.w600 : FontWeight.w400,
          color: granted ? grantedColor : cs.onSurface,
        ),
      ),
      trailing: loading
          ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
          : Icon(
              granted ? Icons.check_circle : Icons.check_circle_outline,
              color: granted ? grantedColor : cs.outline,
              size: 22,
            ),
      onTap: onTap,
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }

  Widget _buildPathModeTile(BuildContext context, RiverPathMode mode, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    bool selected = RiverSettings.instance.pathMode == mode;
    return ListTile(
      title: Text(title, style: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? cs.primary : cs.onSurface,
      )),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
      onTap: () => _saveSettings(pathMode: mode),
    );
  }

  Widget _buildStyleTile(BuildContext context, RiverStyle style, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    bool selected = RiverSettings.instance.style == style;
    return ListTile(
      title: Text(title, style: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? cs.primary : cs.onSurface,
      )),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
      onTap: () => _saveSettings(style: style),
    );
  }

  Widget _buildSlider(BuildContext context, String label, double value, double min, double max, ValueChanged<double> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface)),
              Text(value.toStringAsFixed(2), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.surfaceContainerHighest,
            thumbColor: cs.primary,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 漂浮速度倍数滑块：范围 0.02x～2x，左=0.02x（慢）右=2x（快）；1x=60 秒；内部为过屏时间（秒）
  Widget _buildDriftSpeedMultiplierSlider(BuildContext context, double seconds) {
    final cs = Theme.of(context).colorScheme;
    const minSec = kDriftCrossScreenMinSeconds;  // 2x，快（60/2）
    const maxSec = kDriftCrossScreenMaxSeconds;  // 0.02x，慢（60/0.02）
    final logMin = math.log(minSec);
    final logMax = math.log(maxSec);
    // linear 0 = 左 = 慢 = maxSec(0.02x)，linear 1 = 右 = 快 = minSec(2x)
    final linear = (logMax - math.log(seconds.clamp(minSec, maxSec))) / (logMax - logMin);
    final multiplier = _secondsToMultiplier(seconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('漂浮速度倍数', style: TextStyle(fontSize: 14, color: cs.onSurface)),
              Text(
                _formatDriftMultiplier(multiplier),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.surfaceContainerHighest,
            thumbColor: cs.primary,
          ),
          child: Slider(
            value: linear,
            min: 0,
            max: 1,
            onChanged: (linearVal) {
              final sec = math.exp(logMax - linearVal * (logMax - logMin));
              _saveSettings(driftCrossScreenSeconds: sec);
            },
          ),
        ),
      ],
    );
  }
}
