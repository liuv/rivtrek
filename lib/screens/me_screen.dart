import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../providers/challenge_provider.dart';
import 'settings_screen.dart';
import 'package:rivtrek/services/database_service.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline_page.dart';
import 'package:rivtrek/screens/share_preview_sheet.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  void _navigateToChallengeRecords(
      BuildContext context, TimelineAxisMode mode) async {
    final activities = await DatabaseService.instance.getAllActivities();
    final weathers = await DatabaseService.instance.getAllWeather();
    final events = await DatabaseService.instance.getAllEvents();

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TimelinePage(
            activities: activities,
            weathers: weathers,
            events: events,
            mode: mode,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<ChallengeProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Stack(
        children: [
          // Background subtle decoration or gradient could go here
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  // User Profile Section
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person_outline_rounded,
                            size: 40, color: Color(0xFF888888)),
                      ),
                      const SizedBox(width: 20),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "江河行者",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w300,
                              color: Color(0xFF222222),
                            ),
                          ),
                          Text(
                            "步履不停，终达江海",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                              color: Color(0xFF888888),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                  // Stats Section
                  _buildStatItem("当前挑战", challenge.activeRiver?.name ?? "未选择",
                      Icons.explore_outlined),
                  _buildStatItem(
                      "累计徒步",
                      "${challenge.currentDistance.toStringAsFixed(1)} km",
                      Icons.auto_awesome_outlined),
                  _buildStatItem(
                      "解锁河段",
                      "${challenge.allSubSections.indexWhere((s) => s.name == challenge.currentSubSection?.name) + 1} / ${challenge.allSubSections.length}",
                      Icons.waves_rounded),
                  _buildStatItem("收集物件", "12 个", Icons.inventory_2_outlined),
                  const SizedBox(height: 40),

                  // 勋章成就墙
                  const Text(
                    "江河勋章",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: challenge.allSubSections.length,
                      itemBuilder: (context, index) {
                        final sub = challenge.allSubSections[index];
                        final isUnlocked =
                            challenge.currentDistance >= sub.accumulatedLength;
                        final medalIcon = sub.medalIcon;

                        return Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (medalIcon != null)
                                Opacity(
                                  opacity: isUnlocked ? 1.0 : 0.15,
                                  child: Image.asset(
                                    'assets/$medalIcon',
                                    width: 50,
                                    height: 50,
                                    errorBuilder: (context, error,
                                            stackTrace) =>
                                        const Icon(Icons.military_tech_outlined,
                                            color: Colors.black12),
                                  ),
                                )
                              else
                                const Icon(Icons.military_tech_outlined,
                                    color: Colors.black12),
                              if (!isUnlocked)
                                const Icon(Icons.lock_outline_rounded,
                                    size: 16, color: Colors.black26),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 40),
                  const Divider(color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 20),
                  // Settings/Menu
                  _buildMenuItem("分享进度", Icons.share_rounded, onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (ctx) => const SharePreviewSheet(),
                    );
                  }),
                  _buildMenuItem("挑战记录（公里）", Icons.history_rounded,
                      onTap: () => _navigateToChallengeRecords(
                          context, TimelineAxisMode.distanceKm)),
                  _buildMenuItem("挑战记录（日期）", Icons.calendar_month_rounded,
                      onTap: () => _navigateToChallengeRecords(
                          context, TimelineAxisMode.calendarDate)),
                  _buildMenuItem("徒步设置", Icons.settings_outlined, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()),
                    );
                  }),
                  _buildMenuItem("关于涉川", Icons.info_outline_rounded),
                  _buildMenuItem("退出登录", Icons.logout_rounded),
                  const SizedBox(height: 120), // Padding for bottom nav
                ],
              ),
            ),
          ),
          // Glassmorphism Header (Optional for Me Screen if it's scrollable)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 100,
                  padding: const EdgeInsets.only(top: 50, left: 25),
                  color: Colors.white.withOpacity(0.4),
                  child: const Text(
                    "个人中心",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF222222),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: const Color(0xFF0097A7)),
            const SizedBox(width: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: Color(0xFF555555),
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Color(0xFF222222),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(String title, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF888888)),
            const SizedBox(width: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: Color(0xFF555555),
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }
}
