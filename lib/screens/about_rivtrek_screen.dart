import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 关于涉川 - 产品与设计说明页，内容参考 README 产品设计说明。
class AboutRivtrekScreen extends StatelessWidget {
  const AboutRivtrekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(context),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildSectionCard(
                        title: "项目概述",
                        icon: Icons.auto_awesome_outlined,
                        children: [
                          _paragraph(
                              "涉川 (Walking the River) 是一款文艺、极简的健康运动 App。"),
                          _paragraph("将每日步行数映射为在地理名川（如长江）上的虚拟徒步距离，步履不停，终达江海。"),
                          _paragraph(
                              "设计风格：Digital Zen（数字禅意）、极简主义、高通透感、磨砂玻璃效果。"),
                        ],
                      ),
                      _buildSectionCard(
                        title: "视觉规范",
                        icon: Icons.palette_outlined,
                        children: [
                          _bullet("主背景：暖白 #F9F9F9 / 深色模式 #121212"),
                          _bullet("河流流体：电光青 #00E5FF → 深海蓝 #2979FF 动态渐变"),
                          _bullet("文字：纤细无衬线体，主色 #333333"),
                          _bullet("交互：全屏竖排布局，磨砂玻璃菜单与弹出面板"),
                        ],
                      ),
                      _buildSectionCard(
                        title: "核心功能",
                        icon: Icons.waves_rounded,
                        children: [
                          _subTitle("动态流体首页"),
                          _paragraph("步数驱动流体流速，成就增强发光；垂直 S 形流体与 Perlin 噪声动效。"),
                          _subTitle("步数与地理逻辑"),
                          _paragraph(
                              "步长约 0.7m 换算里程，按河段难度系数映射；每河多节点，含里程、环境与 Shader 参数。"),
                          _subTitle("拾遗与成就"),
                          _paragraph("累计里程达节点时触发拾遗/成就弹窗，极简图标，拾取后飞入背包。"),
                        ],
                      ),
                      _buildSectionCard(
                        title: "技术实现",
                        icon: Icons.code_rounded,
                        children: [
                          _bullet(
                              "Flutter：Canvas / CustomPainter、FragmentShader (GLSL)"),
                          _bullet(
                              "状态管理：Provider / Riverpod，shared_preferences 持久化"),
                          _bullet(
                              "传感器：iOS HealthKit、Android Google Fit / Step Counter"),
                        ],
                      ),
                      const SizedBox(height: 100),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 100,
                  padding: const EdgeInsets.only(top: 50, left: 8, right: 8),
                  color: Colors.white.withOpacity(0.6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded,
                            size: 20, color: Color(0xFF555555)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          "关于涉川",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2979FF).withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              "一条江河，一场行走，一次内心的朝圣之旅。",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "涉川 · Walking the River",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: Colors.black.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF0097A7)),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          fontWeight: FontWeight.w300,
          color: Color(0xFF555555),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF00E5FF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w300,
                color: Color(0xFF555555),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF333333),
        ),
      ),
    );
  }
}
