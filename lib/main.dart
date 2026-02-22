import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'screens/flow_screen.dart';
import 'screens/map_screen.dart';
import 'screens/me_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/initial_river_selection_screen.dart';
import 'providers/challenge_provider.dart';
import 'providers/user_profile_provider.dart';
import 'controllers/flow_controller.dart';
import 'repositories/river_repository.dart';
import 'services/database_service.dart';
import 'services/step_sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await StepSyncService.syncAll();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);

  // 启动时请求基础权限
  if (Platform.isIOS) {
    await Geolocator.requestPermission();
    await Permission.sensors.request();
  } else if (Platform.isAndroid) {
    await Geolocator.requestPermission();
    await Permission.activityRecognition.request();
  }

  // 初始化后台任务（行业做法：高频周期 + 不依赖网络，确保日界前能跑一次）
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  // 15 分钟为系统允许的最短周期，避免「最后一次打开 10 点、10 点后步数记到明天」和漏天
  await Workmanager().registerPeriodicTask(
    "1",
    "periodic-sync-task",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.not_required,
    ),
  );

  // 江河挑战列表从配置文件加载，需在 UI 使用前完成
  await RiverRepository.instance.ensureLoaded();

  // 预打开 rivtrek_base，避免首页首次按距离匹配 POI 时与 asset 复制竞态导致偶发匹配不到
  await DatabaseService.instance.baseDatabase;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChallengeProvider()),
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProxyProvider<ChallengeProvider, FlowController>(
          create: (_) => FlowController(),
          update: (_, challenge, flow) => flow!..updateFromChallenge(challenge),
        ),
      ],
      child: const RivtrekApp(),
    ),
  );
}

class RivtrekApp extends StatelessWidget {
  const RivtrekApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '涉川',
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
      ),
      home: const MainContainer(),
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

bool _sensorPermissionHintShownThisLaunch = false;

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  late PageController _pageController;
  /// 是否已完成首次选择河流（null = 仍在读取 pref）
  bool? _hasCompletedInitialRiverSelection;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _loadInitialRiverSelectionFlag();
  }

  Future<void> _loadInitialRiverSelectionFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('has_completed_initial_river_selection') ?? false;
    if (mounted) {
      setState(() => _hasCompletedInitialRiverSelection = completed);
      if (completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowSensorPermissionHint(context));
      }
    }
  }

  void _onInitialRiverSelectionComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_initial_river_selection', true);
    if (mounted) {
      setState(() => _hasCompletedInitialRiverSelection = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowSensorPermissionHint(context));
    }
  }

  Future<void> _maybeShowSensorPermissionHint(BuildContext context) async {
    if (!Platform.isAndroid || _sensorPermissionHintShownThisLaunch) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sensor_permission_hint_disabled') == true) return;
    if (prefs.getString('last_steps_source') == 'health_connect') return;
    bool? batteryOk;
    bool? autoOk;
    try {
      batteryOk = await DisableBatteryOptimization.isBatteryOptimizationDisabled;
      autoOk = await DisableBatteryOptimization.isAutoStartEnabled;
    } catch (_) {
      return;
    }
    if (batteryOk == true && autoOk == true) return;
    _sensorPermissionHintShownThisLaunch = true;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('步数记录建议'),
        content: const Text(
          '您当前使用本机传感器记录步数。为减少某天步数为 0 或漏记的情况，'
          '建议在「行者」→「应用设置」中开启「忽略电池优化」和「自启动」。',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final p = await SharedPreferences.getInstance();
              await p.setBool('sensor_permission_hint_disabled', true);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('您可在「行者」→「应用设置」中重新开启此提醒'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('不再提示'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 首次安装：先选河流，选完再进首页并可能弹省电/自启动
    if (_hasCompletedInitialRiverSelection == false) {
      return InitialRiverSelectionScreen(onComplete: _onInitialRiverSelectionComplete);
    }
    // 未读完 pref 时短暂显示空白/加载，避免闪屏
    if (_hasCompletedInitialRiverSelection != true) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F9F9),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              FlowScreen(),
              MapScreen(),
              MeScreen(),
            ],
          ),
          _buildBottomNavBar(),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Positioned(
      left: 35,
      right: 35,
      bottom: 45,
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(44),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(44),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(Icons.waves_rounded, "涉川", 0),
                _buildNavItem(Icons.map_outlined, "览图", 1),
                _buildNavItem(Icons.person_outline_rounded, "行者", 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        });
      },
      onDoubleTap: () {
        if (index == 0) {
          // 双击 Flow 按钮，回归真实进度
          context.read<ChallengeProvider>().resetToRealDistance();
          HapticFeedback.mediumImpact();
        }
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color:
                  isActive ? const Color(0xFF0097A7) : const Color(0xFF888888),
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF222222)
                    : const Color(0xFF888888),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
