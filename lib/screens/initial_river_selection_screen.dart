// 首次安装时全屏选择挑战河流，选完后进入首页

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/river.dart';
import '../providers/challenge_provider.dart';
import '../repositories/river_repository.dart';
import '../widgets/river_path_overlay.dart';

class InitialRiverSelectionScreen extends StatefulWidget {
  const InitialRiverSelectionScreen({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<InitialRiverSelectionScreen> createState() => _InitialRiverSelectionScreenState();
}

class _InitialRiverSelectionScreenState extends State<InitialRiverSelectionScreen> {
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

  void _onConfirm() {
    if (_rivers.isEmpty) return;
    final selected = _rivers[_currentPage];
    context.read<ChallengeProvider>().switchRiver(selected.id);
    HapticFeedback.mediumImpact();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: cs.primary))
            : Column(
                children: [
                  const SizedBox(height: 32),
                  Text(
                    '选择你的第一条江河',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1.2,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '步履不停，丈量江山',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 32),
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
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rivers.isNotEmpty ? _rivers[_currentPage].color : cs.surfaceContainerHighest,
                          foregroundColor: _rivers.isNotEmpty ? Colors.white : cs.onSurface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 4,
                          shadowColor: _rivers.isNotEmpty ? _rivers[_currentPage].color.withOpacity(0.4) : null,
                        ),
                        child: const Text('开始挑战', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
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
              Image.asset(
                river.coverPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: river.color.withOpacity(0.15),
                  child: Icon(Icons.waves_rounded, size: 120, color: river.color.withOpacity(0.3)),
                ),
              ),
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
              RiverPathOverlay(
                child: const SizedBox.expand(),
                river: river,
                currentKm: context.watch<ChallengeProvider>().activeRiver?.id == river.id
                    ? context.watch<ChallengeProvider>().currentDistance
                    : 0,
                totalKm: river.totalLengthKm,
              ),
              Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: river.color.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "难度 ${'★' * river.difficulty}",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      river.name,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w200, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      river.description,
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85), height: 1.6, fontWeight: FontWeight.w300),
                    ),
                    const Spacer(),
                    _buildStatRow(Icons.straighten_rounded, '全程长度', '${river.totalLengthKm.round()} km'),
                    const SizedBox(height: 12),
                    _buildStatRow(Icons.timer_outlined, '预计耗时', '${(river.totalLengthKm / 10).round()} 天'),
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
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w300)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Colors.white)),
      ],
    );
  }
}
