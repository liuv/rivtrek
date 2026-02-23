import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../providers/challenge_provider.dart';
import 'settings_screen.dart';
import 'package:rivtrek/screens/challenge_records_menu_screen.dart';
import 'package:rivtrek/screens/share_preview_sheet.dart';
import 'package:rivtrek/screens/about_rivtrek_screen.dart';
import 'package:rivtrek/screens/profile_edit_screen.dart';
import 'package:rivtrek/providers/user_profile_provider.dart';
import 'dart:io';

/// 未解锁徽章灰度滤镜（仅解锁后显示彩色）
const ColorFilter _kMedalGrayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
]);

/// 单条勋章数据，用于大图滑动列表
class _MedalItem {
  final String imagePath;
  final String sectionName;
  final bool isUnlocked;
  _MedalItem(this.imagePath, this.sectionName, this.isUnlocked);
}

void _showMedalFullScreen(
  BuildContext context, {
  required List<_MedalItem> medals,
  required int initialIndex,
}) {
  if (medals.isEmpty) return;
  final index = initialIndex.clamp(0, medals.length - 1);
  showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    barrierLabel: '关闭',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _MedalFullScreenView(
      medals: medals,
      initialIndex: index,
      onClose: () => Navigator.of(ctx).pop(),
    ),
  );
}

class _MedalFullScreenView extends StatefulWidget {
  final List<_MedalItem> medals;
  final int initialIndex;
  final VoidCallback onClose;

  const _MedalFullScreenView({
    required this.medals,
    required this.initialIndex,
    required this.onClose,
  });

  @override
  State<_MedalFullScreenView> createState() => _MedalFullScreenViewState();
}

class _MedalFullScreenViewState extends State<_MedalFullScreenView> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentPage = widget.initialIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final medals = widget.medals;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: medals.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final item = medals[index];
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                            child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 未解锁：灰度图；解锁：彩色原图
                              if (item.isUnlocked)
                                Image.asset(
                                  item.imagePath,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.military_tech_outlined,
                                    size: 120,
                                    color: Colors.black26,
                                  ),
                                )
                              else
                                ColorFiltered(
                                  colorFilter: _kMedalGrayscaleFilter,
                                  child: Image.asset(
                                    item.imagePath,
                                    width: 220,
                                    height: 220,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.military_tech_outlined,
                                      size: 120,
                                      color: Colors.black26,
                                    ),
                                  ),
                                ),
                              // 未解锁时在徽章图上叠加锁图标（居中）
                              if (!item.isUnlocked)
                                Positioned.fill(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              // 未解锁时底部条「未解锁」
                              if (!item.isUnlocked)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock_outline_rounded, size: 18, color: Colors.white.withOpacity(0.95)),
                                        const SizedBox(width: 6),
                                        Text(
                                          "未解锁",
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withOpacity(0.95),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            item.sectionName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (!item.isUnlocked)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "尚未解锁",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (medals.length > 1)
                    Text(
                      '${_currentPage + 1} / ${medals.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: widget.onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<ChallengeProvider>();
    final profile = context.watch<UserProfileProvider>();

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
                  // User Profile Section（整行点击进入编辑）
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileEditScreen(),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Row(
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
                            child: profile.avatarPath != null
                                ? ClipOval(
                                    child: Image.file(
                                      File(profile.avatarPath!),
                                      key: ValueKey('avatar_${profile.avatarPath}_${profile.avatarVersion}'),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                              : const Icon(Icons.person_outline_rounded,
                                  size: 40, color: Color(0xFF888888)),
                        ),
                        const SizedBox(width: 20),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.nickname,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFF222222),
                              ),
                            ),
                            Text(
                              profile.signature,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFF888888),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                      ],
                    ),
                  ),
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

                        return GestureDetector(
                          onTap: () {
                            if (medalIcon == null) return;
                            final medalItems = <_MedalItem>[];
                            for (var s in challenge.allSubSections) {
                              if (s.medalIcon != null)
                                medalItems.add(_MedalItem(
                                  'assets/${s.medalIcon}',
                                  s.name,
                                  challenge.currentDistance >= s.accumulatedLength,
                                ));
                            }
                            if (medalItems.isEmpty) return;
                            int initialIndex = 0;
                            for (int i = 0; i < index; i++)
                              if (challenge.allSubSections[i].medalIcon != null) initialIndex++;
                            _showMedalFullScreen(context, medals: medalItems, initialIndex: initialIndex);
                          },
                          child: Container(
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
                              clipBehavior: Clip.none,
                              children: [
                                if (medalIcon != null)
                                  isUnlocked
                                      ? Image.asset(
                                          'assets/$medalIcon',
                                          width: 50,
                                          height: 50,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.military_tech_outlined, color: Colors.black12),
                                        )
                                      : Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // 灰度 + 压低亮度，保留轮廓但增加神秘感
                                            Opacity(
                                              opacity: 0.35,
                                              child: ColorFiltered(
                                                colorFilter: _kMedalGrayscaleFilter,
                                                child: Image.asset(
                                                  'assets/$medalIcon',
                                                  width: 50,
                                                  height: 50,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      const Icon(Icons.military_tech_outlined, color: Colors.black12),
                                                ),
                                              ),
                                            ),
                                            // 徽章上居中锁图标
                                            Icon(Icons.lock_outline_rounded, size: 22, color: Colors.black54),
                                          ],
                                        )
                                else
                                  const Icon(Icons.military_tech_outlined, color: Colors.black12),
                                if (!isUnlocked && medalIcon != null)
                                  Positioned(
                                    bottom: 2,
                                    child: Text("未解锁", style: TextStyle(fontSize: 9, color: Colors.black45)),
                                  ),
                              ],
                            ),
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
                  _buildMenuItem("挑战记录", Icons.history_rounded, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChallengeRecordsMenuScreen(),
                      ),
                    );
                  }),
                  _buildMenuItem("应用设置", Icons.settings_outlined, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()),
                    );
                  }),
                  _buildMenuItem("关于涉川", Icons.info_outline_rounded, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AboutRivtrekScreen(),
                      ),
                    );
                  }),
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
