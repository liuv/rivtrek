// 河川引路人 - 与 Coze 智能体对话的 Provider
// 负责构建位置上下文、管理对话状态

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/river.dart';
import '../models/river_section.dart';
import '../services/coze_service.dart';

class ChatMessage {
  final bool isUser;
  final String content;
  final DateTime at;

  ChatMessage({required this.isUser, required this.content, required this.at});
}

class RiverGuideProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 构建当前行走位置上下文，供智能体介绍风土人情
  String buildLocationContext({
    required River? river,
    required SubSection? currentSubSection,
    required double currentKm,
    required double totalKm,
  }) {
    if (river == null) return '';
    final buf = StringBuffer();
    buf.writeln('河流：${river.name}');
    buf.writeln('总长：${totalKm.toStringAsFixed(0)} 公里');
    buf.writeln('当前累计行走：${currentKm.toStringAsFixed(0)} 公里');
    if (currentSubSection != null) {
      buf.writeln('当前河段：${currentSubSection.name}');
    }
    return buf.toString().trim();
  }

  /// 发送消息并获取回复
  Future<void> sendMessage({
    required String userId,
    required String text,
    required River? river,
    required SubSection? currentSubSection,
    required double currentKm,
    required double totalKm,
  }) async {
    if (text.trim().isEmpty) return;
    final configured = await CozeService.instance.isConfigured;
    if (!configured) {
      _error = '请先在设置中配置 Coze API Token 和 Bot ID';
      notifyListeners();
      return;
    }

    _error = null;
    _messages.add(ChatMessage(isUser: true, content: text.trim(), at: DateTime.now()));
    _isLoading = true;
    notifyListeners();

    final locationContext = buildLocationContext(
      river: river,
      currentSubSection: currentSubSection,
      currentKm: currentKm,
      totalKm: totalKm,
    );

    try {
      final result = await CozeService.instance.sendAndPoll(
        userId: userId,
        message: text.trim(),
        locationContext: locationContext.isNotEmpty ? locationContext : null,
      );

      if (result.answer.isNotEmpty) {
        _messages.add(ChatMessage(
          isUser: false,
          content: result.answer,
          at: DateTime.now(),
        ));
      } else {
        _messages.add(ChatMessage(
          isUser: false,
          content: '（暂无回复，请重试）',
          at: DateTime.now(),
        ));
      }
    } on CozeException catch (e) {
      _error = e.message;
      _messages.add(ChatMessage(
        isUser: false,
        content: '出错了：${e.message}',
        at: DateTime.now(),
      ));
    } on DioException catch (e) {
      final msg = _parseDioError(e);
      _error = msg;
      _messages.add(ChatMessage(
        isUser: false,
        content: '出错了：$msg',
        at: DateTime.now(),
      ));
    } catch (e) {
      _error = e.toString();
      _messages.add(ChatMessage(
        isUser: false,
        content: '出错了：$e',
        at: DateTime.now(),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  static String _parseDioError(DioException e) => parseCozeDioError(e);
}
