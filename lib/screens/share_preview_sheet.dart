import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:rivtrek/models/daily_stats.dart';
import 'package:rivtrek/providers/challenge_provider.dart';
import 'package:rivtrek/services/database_service.dart';
import 'package:rivtrek/widgets/share_card.dart';
import 'package:rivtrek/providers/user_profile_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 分享预览：展示分享卡片，支持「分享图片」生成截图并调起系统分享
class SharePreviewSheet extends StatefulWidget {
  const SharePreviewSheet({super.key});

  @override
  State<SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<SharePreviewSheet> {
  final GlobalKey _cardKey = GlobalKey();
  RiverPoi? _poi;

  void _loadPoi(int numericId, double km) {
    DatabaseService.instance.getNearestPoi(numericId, km).then((p) {
      if (mounted) setState(() => _poi = p);
    });
  }

  Future<void> _captureAndShare() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/rivtrek_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final challenge = context.read<ChallengeProvider>();
      final river = challenge.activeRiver;
      String text = '步履不停，丈量江山 — 涉川 Rivtrek';
      if (river != null) {
        final part =
            '我在涉川 Rivtrek 挑战「${river.name}」，已行至 ${challenge.currentDistance.toStringAsFixed(1)} km，当前河段：${challenge.currentSubSection?.name ?? "—"}';
        String? loc;
        if (_poi != null) {
          final parts = [
            _poi!.province,
            _poi!.city,
            _poi!.district,
            _poi!.township
          ].whereType<String>().where((s) => s.isNotEmpty).toList();
          final addr =
              parts.isEmpty ? (_poi!.formattedAddress ?? '') : parts.join(' ');
          final names = _poi!.poisList
              .map((p) => p.name?.trim())
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .take(3)
              .join('、');
          loc = addr.trim().isNotEmpty ? addr : null;
          if (names.isNotEmpty) loc = loc != null ? '$loc · $names' : names;
        }
        text = loc != null && loc.trim().isNotEmpty
            ? '$part，此刻行至 $loc。步履不停，丈量江山。'
            : '$part。步履不停，丈量江山。';
      }

      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成分享图失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<ChallengeProvider>();
    final profile = context.watch<UserProfileProvider>();
    final river = challenge.activeRiver;

    if (river == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text('请先选择一条江河挑战', style: TextStyle(color: Color(0xFF888888))),
        ),
      );
    }

    final sectionName = challenge.currentSubSection?.name ?? '—';
    final sub = challenge.currentSubSection;
    final medalIconPath =
        sub?.medalIcon != null ? 'assets/${sub!.medalIcon}' : null;

    // 打开弹窗时按当前河流 numericId 与里程拉取一次最近 POI（用数字 id 避免字符串匹配问题）
    if (_poi == null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadPoi(river.numericId, challenge.currentDistance));
    }

    final addressParts = _poi != null
        ? [_poi!.province, _poi!.city, _poi!.district, _poi!.township]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    final locationLabel = _poi != null
        ? (addressParts.isEmpty
            ? (_poi!.formattedAddress ?? '')
            : addressParts.join(' '))
        : null;
    final poiNames = _poi != null
        ? _poi!.poisList
            .map((p) => p.name?.trim())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join('、')
        : null;
    final hasPoiNames = poiNames != null && poiNames.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '分享进度',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            ShareCardWidget(
              repaintBoundaryKey: _cardKey,
              riverName: river.name,
              totalKm: river.totalLengthKm,
              currentKm: challenge.currentDistance,
              sectionName: sectionName,
              themeColor: river.color,
              coverPath: river.coverPath.isNotEmpty ? river.coverPath : null,
              riverForPathOverlay: river,
              medalIconPath: medalIconPath,
              locationLabel: locationLabel,
              poiNames: hasPoiNames ? poiNames : null,
              displayName: profile.displayNameForShare,
              avatarPath: profile.avatarPath,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _captureAndShare,
                icon: const Icon(Icons.share_rounded, size: 20),
                label: const Text('分享图片'),
                style: FilledButton.styleFrom(
                  backgroundColor: river.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
