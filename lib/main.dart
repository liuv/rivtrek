import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const RiverMeetApp());
}

class RiverMeetApp extends StatelessWidget {
  const RiverMeetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '遇见江河',
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Inter',
      ),
      home: const FlowScreen(),
    );
  }
}

class RiverSection {
  final String name;
  final String themeColor;
  final List<SubSection> subSections;

  RiverSection.fromJson(Map<String, dynamic> json)
      : name = json['section_name'],
        themeColor = json['theme_color'],
        subSections = (json['sub_sections'] as List)
            .map((s) => SubSection.fromJson(s, json['theme_color']))
            .toList();
}

class SubSection {
  final String name;
  final double accumulatedLength;
  final double baseFlowSpeed;
  final int difficulty;
  final String environmentType;
  final String landmarks;
  final Color color;

  SubSection.fromJson(Map<String, dynamic> json, String defaultColor)
      : name = json['sub_section_name'],
        accumulatedLength = json['accumulated_length_km'].toDouble(),
        baseFlowSpeed = json['base_flow_speed'].toDouble(),
        difficulty = json['difficulty_rating'],
        environmentType = json['environment_type'],
        landmarks = json['core_landmarks'],
        color = _parseColor(defaultColor);

  static Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }
}

class FlowScreen extends StatefulWidget {
  const FlowScreen({super.key});

  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen> with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late AnimationController _controller;
  late Stopwatch _stopwatch;
  
  List<SubSection> _allSubSections = [];
  SubSection? _currentSubSection;
  double _currentDistance = 0.0;
  final double _stepLengthKm = 0.0007;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadShader();
    _stopwatch = Stopwatch()..start();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), 
    )..addListener(() {
      setState(() {}); // 核心修复：确保每一帧都触发重绘
    })..repeat();
  }

  Future<void> _loadData() async {
    try {
      final String response = await rootBundle.loadString('assets/json/rivers/yangtze_full.json');
      final data = json.decode(response);
      final List sections = data['challenge_sections'];
      List<SubSection> flatList = [];
      for (var s in sections) {
        flatList.addAll(RiverSection.fromJson(s).subSections);
      }
      setState(() {
        _allSubSections = flatList;
        _updateCurrentProgress(0);
      });
    } catch (e) {
      debugPrint("Error loading river data: $e");
    }
  }

  void _updateCurrentProgress(double distance) {
    _currentDistance = distance;
    SubSection? found;
    for (var sub in _allSubSections) {
      if (distance <= sub.accumulatedLength) {
        found = sub;
        break;
      }
    }
    setState(() {
      _currentSubSection = found ?? (_allSubSections.isNotEmpty ? _allSubSections.last : null);
    });
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/river.frag');
      setState(() {
        _shader = program.fragmentShader();
      });
    } catch (e) {
      debugPrint("Shader load error: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allSubSections.isEmpty || _shader == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sub = _currentSubSection!;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RiverShaderPainter(
                shader: _shader!,
                time: _stopwatch.elapsedMilliseconds / 1000.0,
                // 湍流度受 difficulty 影响更加明显
                turbulence: 0.3 + (sub.difficulty * 0.6), 
                width: 0.16 + (sub.baseFlowSpeed * 0.04),
                // 流速受 baseFlowSpeed 驱动，确保差异化
                speed: 0.15 + (sub.baseFlowSpeed * 0.4), 
                themeColor: sub.color,
                offset: _currentDistance / 10.0, 
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 25),
                _buildHeader(sub),
                const Spacer(flex: 3),
                _buildStepsAndProgress(),
                const Spacer(flex: 4),
              ],
            ),
          ),
          _buildBottomNavBar(),
          _buildDebugSlider(),
        ],
      ),
    );
  }

  Widget _buildHeader(SubSection sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(sub.name.split('·')[0], style: const TextStyle(color: Color(0xFF222222), fontSize: 18, fontWeight: FontWeight.w400)),
              const Icon(Icons.wb_sunny_outlined, size: 20, color: Color(0xFF222222)),
            ],
          ),
          const SizedBox(height: 4),
          Text(sub.name, style: TextStyle(color: const Color(0xFF222222).withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w300)),
        ],
      ),
    );
  }

  Widget _buildStepsAndProgress() {
    int steps = (_currentDistance / _stepLengthKm).floor();
    return Column(
      children: [
        Text(
          steps.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'),
          style: const TextStyle(color: Color(0xFF222222), fontSize: 110, fontWeight: FontWeight.w100, letterSpacing: -4),
        ),
        const SizedBox(height: 5),
        Text("已航行 ${_currentDistance.toStringAsFixed(1)} km / 6387 km", style: TextStyle(color: const Color(0xFF555555).withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w300, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Positioned(
      left: 35, right: 35, bottom: 45,
      child: Container(
        height: 85,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), borderRadius: BorderRadius.circular(44)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(44),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _buildNavItem(Icons.waves_rounded, "Flow", true),
              _buildNavItem(Icons.map_outlined, "Map", false),
              _buildNavItem(Icons.person_outline_rounded, "Me", false),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: isActive ? const Color(0xFF0097A7) : const Color(0xFF888888), size: 26),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: isActive ? const Color(0xFF222222) : const Color(0xFF888888), fontSize: 10)),
    ]);
  }

  Widget _buildDebugSlider() {
    return Positioned(top: 150, right: -100, child: Transform.rotate(angle: math.pi / 2, child: SizedBox(width: 300, child: Slider(value: _currentDistance, max: 6387, onChanged: (v) => _updateCurrentProgress(v), activeColor: Colors.cyan.withOpacity(0.3)))));
  }
}

class RiverShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final double turbulence;
  final double width;
  final double speed;
  final Color themeColor;
  final double offset;

  RiverShaderPainter({required this.shader, required this.time, required this.turbulence, required this.width, required this.speed, required this.themeColor, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, time);
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);
    shader.setFloat(3, speed);
    shader.setFloat(4, turbulence);
    shader.setFloat(5, width);
    shader.setFloat(6, themeColor.red / 255.0);
    shader.setFloat(7, themeColor.green / 255.0);
    shader.setFloat(8, themeColor.blue / 255.0);
    shader.setFloat(9, offset);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant RiverShaderPainter oldDelegate) => true;
}
