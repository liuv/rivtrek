import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:rivtrek/constants/share_phrases.dart';
import 'package:rivtrek/controllers/flow_controller.dart';
import 'package:rivtrek/models/daily_stats.dart';
import 'package:rivtrek/providers/challenge_provider.dart';
import 'package:rivtrek/services/database_service.dart';
import 'package:dio/dio.dart';
import 'package:rivtrek/services/coze_service.dart';
import 'package:rivtrek/widgets/share_card.dart';
import 'package:rivtrek/providers/user_profile_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 分享预览：展示分享卡片，支持「分享图片」生成截图并调起系统分享
class SharePreviewSheet extends StatefulWidget {
  const SharePreviewSheet({super.key});

  @override
  State<SharePreviewSheet> createState() => _SharePreviewSheetState();
}

const String _prefClosingPhrase = 'share_closing_phrase';
const String _prefChallengeStartDate = 'challenge_start_date';

class _SharePreviewSheetState extends State<SharePreviewSheet> {
  final GlobalKey _cardKey = GlobalKey();
  RiverPoi? _poi;
  int? _daysSinceStart;
  int _selectedPhraseIndex = 0;
  String _customPhraseText = '';
  bool _phraseLoaded = false;
  final TextEditingController _customPhraseController = TextEditingController();
  final FocusNode _customPhraseFocus = FocusNode();

  @override
  void dispose() {
    _customPhraseController.dispose();
    _customPhraseFocus.dispose();
    super.dispose();
  }

  Future<void> _loadDaysAndPhrase() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString(_prefChallengeStartDate);
    if (startStr != null && startStr.isNotEmpty) {
      try {
        final start = DateFormat('yyyy-MM-dd').parse(startStr);
        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final days = today.difference(start).inDays;
        if (mounted) setState(() => _daysSinceStart = days >= 0 ? days : 0);
      } catch (_) {}
    }
    final saved = prefs.getString(_prefClosingPhrase);
    if (saved != null && saved.trim().isNotEmpty) {
      final idx = kShareClosingPhraseOptions.indexOf(saved.trim());
      if (mounted) {
        setState(() {
          if (idx >= 0) {
            _selectedPhraseIndex = idx;
            _customPhraseText = '';
          } else {
            _selectedPhraseIndex = -1;
            _customPhraseText = saved.trim();
            _customPhraseController.text = _customPhraseText;
          }
          _phraseLoaded = true;
        });
      }
      return;
    }
    if (mounted) setState(() => _phraseLoaded = true);
  }

  String get _effectiveClosingPhrase {
    if (_selectedPhraseIndex >= 0 && _selectedPhraseIndex < kShareClosingPhraseOptions.length) {
      return kShareClosingPhraseOptions[_selectedPhraseIndex];
    }
    return _customPhraseText.trim().isEmpty ? kShareClosingPhraseDefault : _customPhraseText.trim();
  }

  Future<void> _saveClosingPhrase(String phrase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefClosingPhrase, phrase);
  }

  void _loadPoi(int numericId, double km) {
    DatabaseService.instance.getNearestPoi(numericId, km).then((p) {
      if (mounted) setState(() => _poi = p);
    });
  }

  /// 落款：单行展示当前结语 + 笔形编辑图标，弱交互，不编辑也可直接分享
  Widget _buildClosingPhraseRow(Color themeColor) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showClosingPhrasePicker(themeColor),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _effectiveClosingPhrase,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1.2,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClosingPhrasePicker(Color themeColor) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '落款结语',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(kShareClosingPhraseOptions.length, (i) {
                  final selected = _selectedPhraseIndex == i;
                  return ListTile(
                    title: Text(
                      kShareClosingPhraseOptions[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected ? themeColor : cs.onSurface,
                        letterSpacing: 0.8,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_rounded, size: 20, color: themeColor)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedPhraseIndex = i;
                        _saveClosingPhrase(kShareClosingPhraseOptions[i]);
                      });
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
                if (CozeService.instance.isConfiguredSync)
                  ListTile(
                    leading: Icon(Icons.auto_awesome, size: 20, color: themeColor),
                    title: Text(
                      'AI 生成诗词签名',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                        letterSpacing: 0.8,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _generatePoeticSignature(themeColor);
                    },
                  ),
                ListTile(
                  title: Text(
                    '自定义一句',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _selectedPhraseIndex == -1 ? FontWeight.w500 : FontWeight.w400,
                      color: _selectedPhraseIndex == -1
                          ? themeColor
                          : cs.onSurface,
                      letterSpacing: 0.8,
                    ),
                  ),
                  trailing: _selectedPhraseIndex == -1
                      ? Icon(Icons.check_rounded, size: 20, color: themeColor)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showCustomPhraseDialog(themeColor);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generatePoeticSignature(Color themeColor) async {
    if (!await CozeService.instance.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置 Coze API Token 和 Bot ID')),
        );
      }
      return;
    }
    final challenge = context.read<ChallengeProvider>();
    final profile = context.read<UserProfileProvider>();
    final river = challenge.activeRiver;
    if (river == null) return;

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text('正在生成诗词签名…', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
            ],
          ),
        ),
      );
    }

    try {
      final userId = await CozeService.instance.getOrCreateUserId();
      final phrase = await CozeService.instance.generatePoeticSignature(
        userId: userId,
        nickname: profile.displayNameForShare,
        riverName: river.name,
        sectionName: challenge.currentSubSection?.name ?? '—',
        currentKm: challenge.currentDistance,
        totalKm: river.totalLengthKm,
      );
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        setState(() {
          _selectedPhraseIndex = -1;
          _customPhraseText = phrase;
          _customPhraseController.text = phrase;
          _saveClosingPhrase(phrase);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('诗词签名已生成'), duration: Duration(seconds: 2)),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败：${parseCozeDioError(e)}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  void _showCustomPhraseDialog(Color themeColor) {
    final controller = TextEditingController(text: _customPhraseText);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          title: Text(
            '自定义落款',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: kShareClosingPhraseDefault,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            maxLength: 24,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
              setState(() {
                _selectedPhraseIndex = -1;
                _customPhraseText = v.isEmpty ? kShareClosingPhraseDefault : v;
                _customPhraseController.text = _customPhraseText;
                _saveClosingPhrase(_customPhraseText);
              });
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: themeColor),
            child: const Text('确定'),
          ),
        ],
      );
      },
    );
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
              .map((p) => p.displayNameWithDirection)
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
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Center(
          child: Text('请先选择一条江河挑战', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final sectionName = challenge.currentSubSection?.name ?? '—';
    final sub = challenge.currentSubSection;
    final medalIconPath =
        sub?.medalIcon != null ? 'assets/${sub!.medalIcon}' : null;

    // 打开弹窗时按当前河流 numericId 与里程拉取一次最近 POI；并加载开始天数与结语
    if (_poi == null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadPoi(river.numericId, challenge.currentDistance));
    }
    if (!_phraseLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDaysAndPhrase());
    }

    final flowController = context.read<FlowController>();
    final cumulativeSteps = flowController.cumulativeSteps;
    final dailySteps = flowController.displaySteps;

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
            .map((p) => p.displayNameWithDirection)
            .where((s) => s.isNotEmpty)
            .join('、')
        : null;
    final hasPoiNames = poiNames != null && poiNames.isNotEmpty;

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                color: cs.onSurface,
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
              daysSinceStart: _daysSinceStart ?? 0,
              totalSteps: cumulativeSteps,
              dailySteps: dailySteps,
              closingPhrase: _effectiveClosingPhrase,
            ),
            const SizedBox(height: 12),
            _buildClosingPhraseRow(river.color),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _captureAndShare,
                icon: const Icon(Icons.share_rounded, size: 20),
                label: const Text('分享图片'),
                style: FilledButton.styleFrom(
                  backgroundColor: river.color,
                  foregroundColor: cs.onPrimary,
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
