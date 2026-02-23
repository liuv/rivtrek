// 沉浸听水 / 河声：根据天气与昼夜的实景混音，用于正念冥想与沉浸感

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flow_controller.dart';
import '../models/ambient_mix.dart';
import '../models/daily_stats.dart';
import '../services/ambient_audio_service.dart';

class ImmersiveListenScreen extends StatefulWidget {
  const ImmersiveListenScreen({super.key});

  @override
  State<ImmersiveListenScreen> createState() => _ImmersiveListenScreenState();
}

class _ImmersiveListenScreenState extends State<ImmersiveListenScreen> {
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAmbient());
  }

  void _startAmbient() {
    final controller = context.read<FlowController>();
    final now = DateTime.now();
    final weather = AmbientMixRecipe.weatherTypeFromWmoCode(controller.wmoCode);
    final isNight = now.hour < 6 || now.hour >= 18;
    final spec = AmbientMixRecipe.compute(
      weather,
      isNight: isNight,
      month: now.month,
      context: AmbientContext.immersive,
    );
    if (mounted) setState(() => _status = '${weather.label} · ${isNight ? "夜" : "昼"}');
    AmbientAudioService.playAmbient(spec);
  }

  @override
  void dispose() {
    AmbientAudioService.stopAmbient();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '河声',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w300,
                            color: Colors.white.withOpacity(0.95),
                            letterSpacing: 2,
                          ),
                        ),
                        if (_status.isNotEmpty)
                          Text(
                            _status,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  '听水 · 正念',
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 6,
                    color: Colors.white38,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Text(
                '根据当前天气与昼夜混音，河水、风雨、蛙鸣与雷声随实景变化。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
