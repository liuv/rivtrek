import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/river_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
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
        title: const Text('效果设置', style: TextStyle(fontWeight: FontWeight.w300)),
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
            ],
          );
        }
      ),
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
