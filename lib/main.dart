import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/flow_screen.dart';
import 'screens/map_screen.dart';
import 'screens/me_screen.dart';
import 'providers/challenge_provider.dart';
import 'controllers/flow_controller.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async => Future.value(true));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 启动时仅请求基础权限，避开复杂的健康授权
  if (Platform.isIOS) {
    await Geolocator.requestPermission();
    await Permission.sensors.request();
  }
  
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChallengeProvider()),
        ChangeNotifierProxyProvider<ChallengeProvider, FlowController>(
          create: (_) => FlowController(),
          update: (_, challenge, flow) => flow!..updateFromChallenge(challenge),
        ),
      ],
      child: const RiverMeetApp(),
    ),
  );
}

class RiverMeetApp extends StatelessWidget {
  const RiverMeetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '徒步江河',
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

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                _buildNavItem(Icons.waves_rounded, "徒步", 0),
                _buildNavItem(Icons.map_outlined, "地图", 1),
                _buildNavItem(Icons.person_outline_rounded, "我的", 2),
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
              color: isActive ? const Color(0xFF0097A7) : const Color(0xFF888888),
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF222222) : const Color(0xFF888888),
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
