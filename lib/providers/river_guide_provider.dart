// 江川向导 - 与 Coze 智能体对话的 Provider
// 负责构建位置上下文、管理对话状态

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/coze_context_mode.dart';
import '../models/river.dart';
import '../models/river_section.dart';
import '../services/coze_service.dart';
import '../services/database_service.dart';

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

  /// 构建当前行走位置上下文，供智能体使用。
  /// [mode] 决定上传内容：对话/今日总结含最近三天，此地风土/诗词签名不含；今后可再按场景扩展（如是否带 POI）。
  Future<String> buildLocationContext({
    required River? river,
    required SubSection? currentSubSection,
    required double currentKm,
    required double totalKm,
    CozeContextMode mode = CozeContextMode.chat,
  }) async {
    if (river == null) return '';
    final buf = StringBuffer();

    buf.writeln('河流：${river.name}');
    buf.writeln('总长：${totalKm.toStringAsFixed(0)} 公里');
    buf.writeln('当前累计行走（从挑战开始至今）：${currentKm.toStringAsFixed(0)} 公里（虚拟里程，非单日行走）');
    if (currentSubSection != null) {
      buf.writeln('当前河段：${currentSubSection.name}');
    }

    if (mode.includeRecentThreeDays) {
      final activities = await DatabaseService.instance.getActivitiesForLast3Days(river.id);
      final now = DateTime.now();
      final labels = ['今天', '昨天', '前天'];
      final dates = [
        DateFormat('yyyy-MM-dd').format(now),
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1))),
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 2))),
      ];
      buf.writeln();
      buf.writeln('【最近三天步数/里程】每天两项：当日行走（仅该日步数换算）、当日结束累计（该日结束时总里程）');
      for (var i = 0; i < 3; i++) {
        final a = activities[dates[i]];
        if (a != null) {
          buf.writeln('- ${labels[i]}（${dates[i]}）：步数 ${a.steps}，当日行走 ${a.distanceKm.toStringAsFixed(1)} 公里，当日结束累计 ${a.accumulatedDistanceKm.toStringAsFixed(1)} 公里');
        } else {
          buf.writeln('- ${labels[i]}（${dates[i]}）：无数据');
        }
      }
    }

    // 当前位置：与首页一致，从 rivtrekbase 查最近 POI、地址、下一站
    final nearestPoi = await DatabaseService.instance.getNearestPoi(river.numericId, currentKm);
    final nextPoi = await DatabaseService.instance.getNextPoiWithDistinctAddress(
      river.numericId, currentKm, nearestPoi?.formattedAddress,
    );
    if (nearestPoi != null || nextPoi != null) {
      buf.writeln();
      buf.writeln('【当前位置】');
      if (nearestPoi != null) {
        final addr = nearestPoi.formattedAddress?.trim() ?? nearestPoi.shortLabel;
        if (addr.isNotEmpty) buf.writeln('- 地址：$addr');
        final poiNames = nearestPoi.poisList
            .map((p) => p.displayNameWithDirection)
            .where((s) => s.isNotEmpty)
            .take(5)
            .join('、');
        if (poiNames.isNotEmpty) buf.writeln('- 附近 POI：$poiNames');
      }
      if (nextPoi != null) {
        final dist = (nextPoi.distanceKm - currentKm).toStringAsFixed(1);
        buf.writeln('- 下一站：${nextPoi.shortLabelForNextStop}（还有 $dist 公里）');
      }
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

    final locationContext = await buildLocationContext(
      river: river,
      currentSubSection: currentSubSection,
      currentKm: currentKm,
      totalKm: totalKm,
      mode: CozeContextMode.chat,
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
