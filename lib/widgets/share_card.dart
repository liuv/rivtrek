import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/river.dart';
import 'river_path_overlay.dart';

/// 用于生成分享图片的卡片：封面图、河流名、进度条、河段徽章、此刻行至地点/POI、slogan
class ShareCardWidget extends StatelessWidget {
  final String riverName;
  final double totalKm;
  final double currentKm;
  final String sectionName;
  final Color themeColor;
  /// 江河封面图 asset 路径，如 "assets/images/cover_yangtze.webp"
  final String? coverPath;
  /// 用于在封面上绘制路径与当前位置；为 null 则不绘制
  final River? riverForPathOverlay;
  /// 当前河段徽章 asset 路径，如 "assets/icons/medal_xxx.webp"
  final String? medalIconPath;
  /// 此刻行至的地点文案（省市区或 formattedAddress）
  final String? locationLabel;
  /// 附近 POI 名称，多个用顿号拼接，可为 null
  final String? poiNames;
  /// 分享卡顶部展示的用户昵称；空则显示「涉川」
  final String? displayName;
  /// 用户头像文件路径；为 null 时显示昵称首字或默认
  final String? avatarPath;
  final GlobalKey? repaintBoundaryKey;
  /// 挑战已开始天数；为 null 时不显示「Xxx 之旅 开始了 N 天」
  final int? daysSinceStart;
  /// 累计步数；为 null 时不显示
  final int? totalSteps;
  /// 今日步数；为 null 时不显示
  final int? dailySteps;
  /// 底部结语（用户可选或自定义）；为空时使用默认「步履不停 丈量江山」
  final String? closingPhrase;

  const ShareCardWidget({
    super.key,
    required this.riverName,
    required this.totalKm,
    required this.currentKm,
    required this.sectionName,
    required this.themeColor,
    this.coverPath,
    this.riverForPathOverlay,
    this.medalIconPath,
    this.locationLabel,
    this.poiNames,
    this.displayName,
    this.avatarPath,
    this.repaintBoundaryKey,
    this.daysSinceStart,
    this.totalSteps,
    this.dailySteps,
    this.closingPhrase,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalKm > 0 ? (currentKm / totalKm).clamp(0.0, 1.0) : 0.0;
    final hasCover = coverPath != null && coverPath!.isNotEmpty;
    final hasLocation = (locationLabel != null && locationLabel!.trim().isNotEmpty) ||
        (poiNames != null && poiNames!.trim().isNotEmpty);

    final cornerColor = Color.lerp(themeColor, Colors.black, 0.25) ?? themeColor;

    // 展示层：圆角 + 阴影；截图层：RepaintBoundary 内为完整矩形，分享出去无白边、无圆角
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: RepaintBoundary(
          key: repaintBoundaryKey,
          child: Container(
            width: 375,
            height: 560,
            decoration: BoxDecoration(
              color: hasCover ? null : themeColor,
              gradient: hasCover ? null : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  themeColor.withOpacity(0.85),
                  themeColor.withOpacity(0.95),
                  cornerColor,
                ],
              ),
            ),
            child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：封面图或纯渐变
              if (hasCover) ...[
                Image.asset(
                  coverPath!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallbackGradient(),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        themeColor.withOpacity(0.35),
                        themeColor.withOpacity(0.6),
                        themeColor.withOpacity(0.85),
                        Colors.black.withOpacity(0.75),
                      ],
                    ),
                  ),
                ),
                if (riverForPathOverlay != null)
                  RiverPathOverlay(
                    child: const SizedBox.expand(),
                    river: riverForPathOverlay!,
                    currentKm: currentKm,
                    totalKm: totalKm,
                  ),
              ],
              // 无封面时的水纹装饰
              if (!hasCover) ...[
                Positioned(
                  right: -40,
                  bottom: 80,
                  child: Icon(Icons.waves_rounded, size: 180, color: Colors.white.withOpacity(0.06)),
                ),
                Positioned(
                  left: -20,
                  top: 120,
                  child: Icon(Icons.waves_rounded, size: 100, color: Colors.white.withOpacity(0.05)),
                ),
              ],
              // 内容
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white.withOpacity(0.9),
                          backgroundImage: avatarPath != null && avatarPath!.isNotEmpty
                              ? FileImage(File(avatarPath!))
                              : null,
                          child: avatarPath == null || avatarPath!.isEmpty
                              ? Text(
                                  (displayName ?? '涉川').isNotEmpty
                                      ? (displayName ?? '涉川').substring(0, 1)
                                      : '涉',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: themeColor,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          displayName?.trim().isEmpty ?? true ? '涉川' : (displayName ?? '涉川'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 4,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      riverName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 1,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "已行至 ${currentKm.toStringAsFixed(1)} km",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "全程 ${totalKm.round()} km",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 河段名 + 徽章
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.explore_rounded, size: 16, color: Colors.white.withOpacity(0.95)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    sectionName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white.withOpacity(0.95),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (medalIconPath != null && medalIconPath!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Opacity(
                              opacity: 0.85,
                              child: Image.asset(
                                medalIconPath!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasLocation) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.place_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "此刻行至",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 2,
                                      color: Colors.white.withOpacity(0.75),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (locationLabel != null && locationLabel!.trim().isNotEmpty)
                                    Text(
                                      locationLabel!.trim(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white.withOpacity(0.95),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (poiNames != null && poiNames!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Icon(Icons.explore_rounded, size: 12, color: Colors.white.withOpacity(0.8)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            poiNames!.trim(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.white.withOpacity(0.88),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (daysSinceStart != null || totalSteps != null || dailySteps != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.timeline_rounded,
                            size: 16,
                            color: Colors.white.withOpacity(0.78),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _daysStepsLine(daysSinceStart, totalSteps, dailySteps),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 1.2,
                              color: Colors.white.withOpacity(0.88),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Text(
                      (closingPhrase?.trim().isEmpty ?? true) ? '步履不停 丈量江山' : closingPhrase!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.5,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "涉川 Rivtrek",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  String _formatSteps(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  /// 文言式一行：历时 X天　行进 X步　今日 X步（有数据就显示，0 也显示）
  String _daysStepsLine(int? daysSinceStart, int? totalSteps, int? dailySteps) {
    final d = daysSinceStart ?? 0;
    final s = totalSteps ?? 0;
    final today = dailySteps ?? 0;
    return '历时 ${d}天　行进 ${_formatSteps(s)} 步　今日 $today 步';
  }

  Widget _buildFallbackGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            themeColor.withOpacity(0.85),
            themeColor.withOpacity(0.95),
            Color.lerp(themeColor, Colors.black, 0.25) ?? themeColor,
          ],
        ),
      ),
    );
  }
}
