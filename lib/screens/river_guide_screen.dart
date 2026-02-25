// 河川引路人 - 与 Coze 智能体对话的聊天界面

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../providers/challenge_provider.dart';
import '../providers/river_guide_provider.dart';
import '../services/coze_service.dart';

class RiverGuideScreen extends StatefulWidget {
  const RiverGuideScreen({super.key});

  @override
  State<RiverGuideScreen> createState() => _RiverGuideScreenState();
}

class _RiverGuideScreenState extends State<RiverGuideScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool? _isConfigured;

  @override
  void initState() {
    super.initState();
    _checkConfigured();
  }

  Future<void> _checkConfigured() async {
    final configured = await CozeService.instance.isConfigured;
    if (mounted) setState(() => _isConfigured = configured);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final guide = context.read<RiverGuideProvider>();
    final challenge = context.read<ChallengeProvider>();
    final userId = await CozeService.instance.getOrCreateUserId();

    await guide.sendMessage(
      userId: userId,
      text: text,
      river: challenge.activeRiver,
      currentSubSection: challenge.currentSubSection,
      currentKm: challenge.currentDistance,
      totalKm: challenge.activeRiver?.totalLengthKm ?? 0,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('河川引路人', style: TextStyle(fontWeight: FontWeight.w300)),
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        actions: [
          if (_isConfigured == true)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '清空对话',
              onPressed: () {
                context.read<RiverGuideProvider>().clearMessages();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<RiverGuideProvider>(
              builder: (context, guide, _) {
                if (guide.messages.isEmpty) {
                  return _buildEmptyState(context);
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: guide.messages.length + (guide.isLoading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (guide.isLoading && i == guide.messages.length) {
                      return _buildTypingBubble(context);
                    }
                    final msg = guide.messages[i];
                    return _buildMessageBubble(context, msg, false);
                  },
                );
              },
            ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final challenge = context.watch<ChallengeProvider>();

    if (_isConfigured == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isConfigured == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 24),
              Text(
                '请先在「应用设置」中配置 Coze API Token 和 Bot ID',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                '配置完成后即可与河川引路人畅聊江河风土、历史典故，并生成个性化诗词签名。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.outline, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final river = challenge.activeRiver?.name ?? '江河';
    final section = challenge.currentSubSection?.name ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.waves_rounded, size: 56, color: cs.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 24),
            Text(
              '河川引路人',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '我是您的江河向导，可为您介绍不同河段的风土人情、历史典故，'
              '也可根据您的行走进度生成个性化诗词签名，便于分享。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, height: 1.5),
            ),
            if (river.isNotEmpty || section.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (river.isNotEmpty)
                      Text('当前挑战：$river', style: TextStyle(fontSize: 14, color: cs.onSurface)),
                    if (section.isNotEmpty)
                      Text('当前河段：$section', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              '试试问我：',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
            const SizedBox(height: 12),
            _buildSuggestionChip(context, '介绍一下我现在所在的河段有什么特色？'),
            _buildSuggestionChip(context, '这里有什么历史典故或传说？'),
            _buildSuggestionChip(context, '为我生成一句诗词签名，用于分享'),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          _controller.text = text;
          _send();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text, style: TextStyle(fontSize: 14, color: cs.onSurface)),
        ),
      ),
    );
  }

  Widget _buildTypingBubble(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary.withValues(alpha: 0.2),
            child: Icon(Icons.waves_rounded, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Text('正在思考…', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg, bool isTyping) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primary.withValues(alpha: 0.2),
              child: Icon(Icons.waves_rounded, size: 18, color: cs.primary),
            ),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: isUser
                  ? Text(msg.content, style: TextStyle(fontSize: 15, color: cs.onSurface))
                  : MarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.5),
                        listBullet: TextStyle(fontSize: 15, color: cs.onSurface),
                      ),
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primary.withValues(alpha: 0.3),
              child: Icon(Icons.person_outline_rounded, size: 18, color: cs.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '输入消息…',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 12),
            Consumer<RiverGuideProvider>(
              builder: (context, guide, _) {
                return IconButton.filled(
                  onPressed: guide.isLoading ? null : _send,
                  icon: guide.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : const Icon(Icons.send_rounded),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
