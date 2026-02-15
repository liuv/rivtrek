// lib/screens/river_selector_sheet.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/river.dart';
import '../providers/challenge_provider.dart';
import '../repositories/river_repository.dart';

class RiverSelectorSheet extends StatefulWidget {
  const RiverSelectorSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RiverSelectorSheet(),
    );
  }

  @override
  State<RiverSelectorSheet> createState() => _RiverSelectorSheetState();
}

class _RiverSelectorSheetState extends State<RiverSelectorSheet> {
  late PageController _pageController;
  int _currentPage = 0;
  List<River> _rivers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _loadRivers();
  }

  Future<void> _loadRivers() async {
    final rivers = await RiverRepository.instance.getAvailableRivers();
    if (mounted) {
      final activeRiverId = context.read<ChallengeProvider>().activeRiver?.id;
      final initialPage = rivers.indexWhere((r) => r.id == activeRiverId);
      
      setState(() {
        _rivers = rivers;
        _isLoading = false;
        _currentPage = initialPage >= 0 ? initialPage : 0;
      });
      
      if (initialPage >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.jumpToPage(initialPage);
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "切换挑战线路",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "步履不停，丈量江山",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.4),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _rivers.length,
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
                        HapticFeedback.lightImpact();
                      },
                      itemBuilder: (context, index) {
                        return _buildRiverCard(_rivers[index], index == _currentPage);
                      },
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildActionButton(),
                  const SizedBox(height: 60),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildRiverCard(River river, bool isSelected) {
    const radius = 24.0;
    return AnimatedScale(
      scale: isSelected ? 1.0 : 0.9,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: river.color.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面图背景，路径在 rivers_config.json 的 cover_path 中配置
              Image.asset(
                river.coverPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: river.color.withOpacity(0.15),
                  child: Icon(Icons.waves_rounded, size: 120, color: river.color.withOpacity(0.3)),
                ),
              ),
              // 渐变遮罩，保证文字可读
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.5),
                      Colors.black.withOpacity(0.75),
                    ],
                  ),
                ),
              ),
              // 卡片内容
              Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: river.color.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "难度 ${'★' * river.difficulty}",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (context.watch<ChallengeProvider>().activeRiver?.id == river.id)
                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      river.name,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      river.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.6,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const Spacer(),
                    _buildStatRow(Icons.straighten_rounded, "全程长度", "${river.totalLengthKm.round()} km"),
                    const SizedBox(height: 12),
                    _buildStatRow(Icons.timer_outlined, "预计耗时", "${(river.totalLengthKm / 10).round()} 天"),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w300),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final activeRiverId = context.watch<ChallengeProvider>().activeRiver?.id;
    final selectedRiver = _rivers[_currentPage];
    final isCurrent = activeRiverId == selectedRiver.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GestureDetector(
        onTap: () {
          if (!isCurrent) {
            context.read<ChallengeProvider>().switchRiver(selectedRiver.id);
            HapticFeedback.mediumImpact();
            Navigator.pop(context);
          } else {
            Navigator.pop(context);
          }
        },
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: isCurrent ? Colors.grey[200] : selectedRiver.color,
            borderRadius: BorderRadius.circular(30),
            boxShadow: isCurrent ? [] : [
              BoxShadow(
                color: selectedRiver.color.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              isCurrent ? "正在挑战中" : "开启 ${selectedRiver.name} 挑战",
              style: TextStyle(
                color: isCurrent ? Colors.black38 : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
