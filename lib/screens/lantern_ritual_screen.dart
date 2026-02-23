// 放河灯/漂流瓶仪式：净心 → 寄愿/寄语 → 步数 → 滑动放灯/放瓶 → 结语（控件复用）

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../controllers/flow_controller.dart';
import '../models/ambient_mix.dart';
import '../services/ambient_audio_service.dart';

/// 仪式页实景混音：淡出时长
const Duration _kRiverSoundFadeOut = Duration(milliseconds: 400);

/// 放灯/放瓶所需最少步数（步数即灵力/缘分）
const int kMinStepsToReleaseLantern = 3000;

enum RitualMode { lantern, bottle }

class LanternRitualScreen extends StatefulWidget {
  const LanternRitualScreen({
    super.key,
    required this.onComplete,
    this.mode = RitualMode.lantern,
    this.wmoCode = 0,
  });

  final void Function(String? wish) onComplete;
  final RitualMode mode;
  /// 当前天气 WMO 码，用于实景混音（0 或未传则按 unknown 处理）
  final int wmoCode;

  @override
  State<LanternRitualScreen> createState() => _LanternRitualScreenState();
}

class _LanternRitualScreenState extends State<LanternRitualScreen>
    with TickerProviderStateMixin {
  int _step = 0;
  final TextEditingController _wishController = TextEditingController();
  double _dragOffset = 0;
  double _lanternOffsetY = 0; // 河灯相对初始位置的垂直偏移（上滑为正）
  double _dragTargetOffsetY = 0; // 手指目标，河灯用弹簧跟随
  bool _released = false;
  Ticker? _flingTicker;
  Simulation? _flingSimulation;
  double _flingElapsed = 0;
  double _flingTriggerDistance = 0;
  late AnimationController _fadeController;
  late AnimationController _dimController;
  late AnimationController _lanternFadeOutController;
  static const int _totalSteps = 5; // 净心、寄语、步数、放灯/放瓶、结语

  bool get _isBottle => widget.mode == RitualMode.bottle;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _dimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _lanternFadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _startRiverAmbient();
    _dimController.forward();
  }

  /// 行业做法：只发指令给 audio_service，加载与混音在 Handler 内执行
  void _startRiverAmbient() {
    final now = DateTime.now();
    final weather = AmbientMixRecipe.weatherTypeFromWmoCode(widget.wmoCode);
    final isNight = now.hour < 6 || now.hour >= 18;
    final spec = AmbientMixRecipe.compute(
      weather,
      isNight: isNight,
      month: now.month,
      context: AmbientContext.ritual,
    );
    AmbientAudioService.playAmbient(spec);
  }

  void _fadeOutRiverSound() {
    AmbientAudioService.stopAmbient();
  }

  @override
  void dispose() {
    _dimController.dispose();
    _lanternFadeOutController.dispose();
    _flingTicker?.dispose();
    _flingTicker = null;
    if (!_released) AmbientAudioService.stopAmbient();
    _wishController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  int get _todaySteps {
    try {
      return context.read<FlowController>().displaySteps;
    } catch (_) {
      return 0;
    }
  }

  bool get _canReleaseBySteps => _todaySteps >= kMinStepsToReleaseLantern;

  void _next() {
    if (_step >= _totalSteps - 1) return;
    setState(() => _step++);
  }

  void _onRelease() {
    if (_released) return;
    _released = true;
    HapticFeedback.mediumImpact();
    _lanternFadeOutController.forward(from: 0);
    _fadeController.forward();
    _fadeOutRiverSound(); // 立即开始声音渐隐，与画面同步，由动到静
    const stayMs = 1550;
    Future.delayed(const Duration(milliseconds: stayMs), () {
      if (!mounted) return;
      final wish = _wishController.text.trim().isEmpty
          ? null
          : _wishController.text.trim();
      widget.onComplete(wish);
      Navigator.of(context).pop();
    });
  }

  /// 松手后惯性：用摩擦模拟，带初速度滑一段再停
  void _startFling(double triggerDistance, double velocityPxPerSec) {
    _flingTriggerDistance = triggerDistance;
    _flingSimulation = FrictionSimulation(0.02, _dragOffset, velocityPxPerSec);
    _flingElapsed = 0;
    _flingTicker?.dispose();
    _flingTicker = createTicker((elapsed) {
      _flingElapsed += elapsed.inMilliseconds / 1000.0;
      final sim = _flingSimulation!;
      final x = sim.x(_flingElapsed);
      if (!mounted || _released) {
        _flingTicker?.dispose();
        _flingTicker = null;
        _flingSimulation = null;
        return;
      }
      setState(() {
        _dragOffset = x.clamp(0.0, double.infinity);
        _lanternOffsetY = _dragOffset;
        if (_dragOffset >= _flingTriggerDistance) {
          _onRelease();
          _flingTicker?.dispose();
          _flingTicker = null;
          _flingSimulation = null;
          return;
        }
        if (sim.isDone(_flingElapsed)) {
          _flingTicker?.dispose();
          _flingTicker = null;
          _flingSimulation = null;
        }
      });
    });
    _flingTicker!.start();
  }

  /// 遮罩不随滑动变化，保持场景切换感，弱化卡顿感
  double _getOverlayOpacity() => 0.78 * _dimController.value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _dimController,
            builder: (context, _) => Container(
              color: Colors.black.withOpacity(_getOverlayOpacity()),
            ),
          ),
          SafeArea(child: _buildStep()),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildCalmMind();
      case 1:
        return _buildWishInput();
      case 2:
        return _buildStepsCheck();
      case 3:
        return _buildSwipeRelease();
      case 4:
        return _buildClosing();
      default:
        return _buildCalmMind();
    }
  }

  Widget _buildCalmMind() {
    final icon = _isBottle ? Icons.send_outlined : Icons.nightlight_round_outlined;
    final text = _isBottle
        ? '请在此刻，静心片刻，只留一封信。'
        : '请在此刻，放下杂念，只留一心愿。';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 56,
            color: Colors.amber.shade200.withOpacity(0.9),
          ),
          const SizedBox(height: 40),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              height: 1.6,
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w300,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 48),
          TextButton(
            onPressed: _next,
            child: Text(
              '下一步',
              style: TextStyle(
                color: Colors.amber.shade200,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWishInput() {
    const suggestions = ['坚持', '自律', '变好', '平安', '成为想成为的人'];
    final title = _isBottle ? '寄语' : '寄愿';
    final subtitle = _isBottle
        ? '写一封随江远行的信，不公开、不炫耀——只给未来的自己或流水。'
        : '写一句只给自己看的话，不公开、不炫耀——这才是真・信念。';
    final hint = _isBottle ? '可留空，或写下心意（128字以内）' : '可留空，或写下心愿';
    final maxLen = _isBottle ? 128 : 20;
    final maxLines = _isBottle ? 5 : 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              letterSpacing: 4,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _wishController,
            maxLength: maxLen,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.95),
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.68),
                fontSize: 16,
              ),
              counterText: '',
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.amber.shade200.withOpacity(0.6)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: suggestions
                .map((s) => ActionChip(
                      label: Text(
                        s,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.45),
                      side: BorderSide(color: Colors.white.withOpacity(0.35)),
                      onPressed: () {
                        _wishController.text = s;
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 48),
          TextButton(
            onPressed: _next,
            child: Text(
              '继续',
              style: TextStyle(
                color: Colors.amber.shade200,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepsCheck() {
    final steps = _todaySteps;
    final ok = _canReleaseBySteps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '今日步数',
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 2,
              color: Colors.white.withOpacity(0.88),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$steps',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w200,
              color: ok ? Colors.amber.shade200 : Colors.white.withOpacity(0.9),
            ),
          ),
          Text(
            '步',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.88),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isBottle
                ? (ok
                    ? '步数即缘分，可以寄出一只漂流瓶。'
                    : '今日步数满 $kMinStepsToReleaseLantern 步，瓶中信更稳；未满也可寄出，心意不减。')
                : (ok
                    ? '步数即灵力，可以点亮一盏河灯。'
                    : '今日步数满 $kMinStepsToReleaseLantern 步，河灯更亮；未满也可放灯，愿心不减。'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 48),
          TextButton(
            onPressed: _next,
            child: Text(
              _isBottle ? (ok ? '寄出' : '仍要寄出') : (ok ? '放灯' : '仍要放灯'),
              style: TextStyle(
                color: Colors.amber.shade200,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 河灯/瓶起始在下 1/3，上滑到上 1/3 释放，与主屏动画起点衔接
  static const double _kLanternSizeBase = 76.0;
  /// 主屏河灯：50 * scale，上 1/3 处 scale≈0.93，视觉尺寸约 46.5
  static const double _kMainScreenLanternSizeAtRelease = 50.0 * 0.93;
  /// 主屏漂流瓶同 50*scale，但释放页瓶子略放大以便与江面漂流瓶视觉一致（瓶图留白多易显小）
  static const double _kMainScreenBottleSizeAtRelease = 58.0;

  Widget _buildSwipeRelease() {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;
    final triggerDistance = h / 3;
    final progress = (triggerDistance <= 0)
        ? 0.0
        : (_dragOffset / triggerDistance).clamp(0.0, 1.0);
    final triggered = _dragOffset >= triggerDistance;

    final releaseSize = _isBottle ? _kMainScreenBottleSizeAtRelease : _kMainScreenLanternSizeAtRelease;
    final scaleAtRelease = releaseSize / _kLanternSizeBase;
    final currentScale = 1.0 + (scaleAtRelease - 1.0) * progress;
    final currentSize = _kLanternSizeBase * currentScale;

    final bottomThird = h * (2 / 3);
    final baseTop = bottomThird - _kLanternSizeBase / 2;
    final lanternTop = (baseTop - _lanternOffsetY).clamp(0.0, h - currentSize);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 24,
          left: 24,
          right: 24,
          child: Text(
            triggered
                ? (_isBottle ? '信随水去。' : '愿随水去。')
                : (_isBottle ? '轻托漂流瓶，向上送入江中。' : '轻托河灯，向上送入江中。'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              letterSpacing: 2,
              height: 1.5,
              color: Colors.white.withOpacity(triggered ? 0.7 : 0.85),
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        Positioned(
          left: (size.width - currentSize) / 2,
          top: lanternTop,
          child: triggered
              ? FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(_lanternFadeOutController),
                  child: _buildReleaseImage(currentSize),
                )
              : GestureDetector(
                  onVerticalDragStart: (_) {
                    if (_released) return;
                    _flingTicker?.dispose();
                    _flingTicker = null;
                    _flingSimulation = null;
                    _dragTargetOffsetY = _dragOffset;
                  },
                  onVerticalDragUpdate: (d) {
                    if (_released) return;
                    setState(() {
                      _dragTargetOffsetY -= d.delta.dy;
                      if (_dragTargetOffsetY < 0) _dragTargetOffsetY = 0;
                      if (_dragTargetOffsetY > triggerDistance) _dragTargetOffsetY = triggerDistance;
                      _dragOffset = _dragTargetOffsetY;
                      _lanternOffsetY = _lanternOffsetY + (_dragTargetOffsetY - _lanternOffsetY) * 0.42;
                      if (_lanternOffsetY < 0) _lanternOffsetY = 0;
                      if (_lanternOffsetY > triggerDistance) _lanternOffsetY = triggerDistance;
                      if (_dragOffset >= triggerDistance) _onRelease();
                    });
                  },
                  onVerticalDragEnd: (d) {
                    if (_released) return;
                    final velocityPxPerSec = d.velocity.pixelsPerSecond.dy;
                    if (velocityPxPerSec.abs() < 20) return;
                    _startFling(triggerDistance, -velocityPxPerSec);
                  },
                  child: _buildReleaseImage(currentSize),
                ),
        ),
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: Column(
            children: [
              if (!triggered)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE4B86A)),
                  ),
                ),
              if (!triggered) const SizedBox(height: 12),
              Text(
                triggered ? (_isBottle ? '瓶已入江。' : '河灯已入江。') : '松手即放。',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 3,
                  color: Colors.white.withOpacity(0.72),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReleaseImage(double size) {
    final assetPath = _isBottle ? 'assets/icons/bottle.png' : 'assets/icons/light.png';
    final fallbackIcon = _isBottle ? Icons.send_outlined : Icons.nightlight_round_outlined;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          fallbackIcon,
          size: size,
          color: Colors.amber.shade200.withOpacity(0.9),
        ),
      ),
    );
  }

  Widget _buildClosing() {
    final text = _isBottle
        ? '你走过的路，会化作江流；\n你写下的字，会装进漂流瓶。\n水会带走，风会读到，未来的自己也会收到。'
        : '你走过的路，会化作江流；\n你许下的愿，会变成河灯。\n风会记得，水会记得，你自己更会记得。';
    return FadeTransition(
      opacity: _fadeController,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                height: 1.85,
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w300,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 从 extraData 解析河灯心愿（仅本地，不公开）
String? parseLanternWishFromExtraData(String extraData) {
  if (extraData.isEmpty || extraData == '{}') return null;
  try {
    final map = jsonDecode(extraData) as Map<String, dynamic>?;
    return map?['wish'] as String?;
  } catch (_) {
    return null;
  }
}
