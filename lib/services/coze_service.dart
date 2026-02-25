// Coze.cn API 服务 - 河川引路人智能体集成
// 文档: https://www.coze.cn/api/open/docs

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:rivtrek/config/coze_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _baseUrl = 'https://api.coze.cn';
const String _prefToken = 'coze_api_token';
const String _prefBotId = 'coze_bot_id';
const String _prefConversationId = 'coze_conversation_id';
const String _prefUserId = 'coze_user_id';

class CozeService {
  static final CozeService instance = CozeService._();
  CozeService._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Content-Type': 'application/json'},
  ));

  String? _patToken;
  String? _botId;

  /// 是否已配置（PAT + bot_id 已配置）
  Future<bool> get isConfigured async {
    if (_botId == null || _botId!.trim().isEmpty) {
      await _loadBotId();
    }
    final b = _botId?.trim();
    if (b == null || b.isEmpty) return false;
    await _loadConfig();
    final t = _patToken?.trim();
    return t != null && t.isNotEmpty;
  }

  /// 同步判断是否已配置（用于 UI 快速判断，可能略滞后）
  bool get isConfiguredSync {
    if (kCozeBotId.trim().isEmpty && (_botId == null || _botId!.trim().isEmpty)) return false;
    if (kCozeBuildTimeConfigured) return true;
    final t = _patToken?.trim();
    return t != null && t.isNotEmpty;
  }

  Future<void> _loadBotId() async {
    if (_botId != null && _botId!.isNotEmpty) return;
    if (kCozeBotId.trim().isNotEmpty) {
      _botId = kCozeBotId.trim();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _botId = prefs.getString(_prefBotId);
  }

  Future<void> _loadConfig() async {
    await _loadBotId();
    if (_patToken != null && _patToken!.isNotEmpty) return;
    if (kCozeBuildTimeConfigured) {
      _patToken = kCozeApiToken.trim();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _patToken = prefs.getString(_prefToken);
  }

  /// 获取当前应使用的 access_token（PAT）
  Future<String> _getToken() async {
    await _loadConfig();
    final t = _patToken?.trim();
    if (t == null || t.isEmpty) {
      throw CozeException(
        isBuildTimeConfigured ? 'Coze 服务暂时不可用' : '请先在设置中配置 Coze API Token',
      );
    }
    return t;
  }

  /// 是否由构建时注入 PAT 配置
  bool get isBuildTimeConfigured => kCozeBuildTimeConfigured;

  /// 保存 API 配置（PAT 模式，开发调试用）
  Future<void> setConfig({required String token, required String botId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefToken, token.trim());
    await prefs.setString(_prefBotId, botId.trim());
    _patToken = token.trim();
    _botId = botId.trim();
  }

  /// 清除配置（PAT）
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefToken);
    await prefs.remove(_prefBotId);
    await prefs.remove(_prefConversationId);
    _patToken = null;
    _botId = null;
  }

  /// 获取或生成 Coze 用户 ID（设备唯一标识）
  Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var uid = prefs.getString(_prefUserId);
    if (uid == null || uid.isEmpty) {
      uid = 'rivtrek_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond % 10000)}';
      await prefs.setString(_prefUserId, uid);
    }
    return uid;
  }

  /// 获取当前 conversation_id（用于续聊）
  Future<String?> getStoredConversationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefConversationId);
  }

  void _storeConversationId(String id) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefConversationId, id);
    });
  }

  Future<Map<String, String>> _authHeaders() async {
    final t = await _getToken();
    return {'Authorization': 'Bearer $t'};
  }

  /// 创建新会话（可选，首次对话时若没有 conversation_id 则创建）
  Future<String> createConversation(String userId) async {
    await _loadConfig();
    final botId = _botId;
    if (botId == null || botId.isEmpty) {
      throw CozeException(
        isBuildTimeConfigured ? 'Coze 服务暂时不可用' : '请先在设置中配置 Coze Bot ID',
      );
    }

    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/conversation/create',
      options: Options(headers: await _authHeaders()),
      data: {
        'bot_id': botId,
        'user_id': userId,
        'connector_id': '1024',
      },
    );

    final data = res.data;
    if (data == null) throw CozeException('创建会话失败：无响应');
    final code = data['code'] as int?;
    if (code != 0) {
      throw CozeException(data['msg']?.toString() ?? '创建会话失败');
    }
    final convId = data['data']?['id']?.toString();
    if (convId == null || convId.isEmpty) {
      throw CozeException('创建会话失败：未返回会话 ID');
    }
    _storeConversationId(convId);
    return convId;
  }

  /// 发送消息并轮询获取回复（非流式）
  /// [conversationId] 可为 null，若为 null 则使用已存会话或创建新会话
  /// [createNewConversation] 为 true 时强制创建新会话（如生成诗词签名，避免上下文干扰）
  /// [userId] 用户唯一标识，建议用设备 ID 或账号 ID
  /// [locationContext] 可选，当前河段/位置上下文，供智能体参考
  Future<CozeChatResult> sendAndPoll({
    String? conversationId,
    bool createNewConversation = false,
    required String userId,
    required String message,
    String? locationContext,
  }) async {
    await _loadConfig();
    final botId = _botId;
    if (botId == null || botId.isEmpty) {
      throw CozeException(
        isBuildTimeConfigured ? 'Coze 服务暂时不可用' : '请先在设置中配置 Coze Bot ID',
      );
    }

    String convId = conversationId ?? '';
    if (convId.isEmpty && !createNewConversation) {
      convId = await getStoredConversationId() ?? '';
    }
    if (convId.isEmpty) {
      convId = await createConversation(userId);
    }

    // 若有位置上下文，拼接到用户消息前作为系统提示（或单独一条）
    String userContent = message;
    if (locationContext != null && locationContext.trim().isNotEmpty) {
      userContent = '【当前行走位置】$locationContext\n\n$message';
    }

    final chatRes = await _dio.post<Map<String, dynamic>>(
      '/v3/chat',
      queryParameters: {'conversation_id': convId},
      options: Options(headers: await _authHeaders()),
      data: {
        'bot_id': botId,
        'user_id': userId,
        'stream': false,
        'auto_save_history': true,
        'additional_messages': [
          {'role': 'user', 'content': userContent, 'content_type': 'text'},
        ],
      },
    );

    final chatData = chatRes.data;
    if (chatData == null) throw CozeException('发送失败：无响应');
    final code = chatData['code'] as int?;
    if (code != 0) {
      throw CozeException(chatData['msg']?.toString() ?? '发送失败');
    }

    final respData = chatData['data'] as Map<String, dynamic>?;
    if (respData == null) throw CozeException('发送失败：无数据');
    final chatId = respData['id']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw CozeException('发送失败：未返回 chat_id');
    }

    // 轮询直到完成
    const pollInterval = Duration(milliseconds: 800);
    const maxAttempts = 90; // 约 72 秒
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(pollInterval);

      final retrieveRes = await _dio.get<Map<String, dynamic>>(
        '/v3/chat/retrieve',
        queryParameters: {
          'conversation_id': convId,
          'chat_id': chatId,
        },
        options: Options(headers: await _authHeaders()),
      );

      final retData = retrieveRes.data;
      if (retData == null) continue;
      final retCode = retData['code'] as int?;
      if (retCode != 0) continue;

      final detail = retData['data'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final status = detail['status']?.toString() ?? '';
      if (status == 'completed') {
        final messages = await _fetchMessages(convId, chatId);
        return CozeChatResult(
          conversationId: convId,
          chatId: chatId,
          answer: messages,
          usage: detail['usage'] as Map<String, dynamic>?,
        );
      }
      if (status == 'failed') {
        final err = detail['last_error'] as Map<String, dynamic>?;
        throw CozeException(err?['msg']?.toString() ?? '生成失败');
      }
      if (status == 'canceled') {
        throw CozeException('对话已取消');
      }
    }

    throw CozeException('等待回复超时，请稍后重试');
  }

  Future<String> _fetchMessages(String conversationId, String chatId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v3/chat/message/list',
      queryParameters: {
        'conversation_id': conversationId,
        'chat_id': chatId,
      },
      options: Options(headers: await _authHeaders()),
    );

    final data = res.data;
    if (data == null || data['code'] != 0) return '';

    final list = data['data'] as List<dynamic>?;
    if (list == null || list.isEmpty) return '';

    final answers = <String>[];
    for (final item in list) {
      final map = item as Map<String, dynamic>?;
      if (map == null) continue;
      final type = map['type']?.toString();
      final role = map['role']?.toString();
      if (type == 'answer' && role == 'assistant') {
        final content = map['content']?.toString();
        if (content != null && content.trim().isNotEmpty) {
          answers.add(content.trim());
        }
      }
    }
    return answers.join('\n\n').trim();
  }

  /// 快捷调用：生成诗词签名（用于分享卡片）
  /// [nickname] 用户昵称
  /// [riverName] 河流名
  /// [sectionName] 当前河段名
  /// [currentKm] 已行走公里数
  /// [totalKm] 总公里数
  Future<String> generatePoeticSignature({
    required String userId,
    required String nickname,
    required String riverName,
    required String sectionName,
    required double currentKm,
    required double totalKm,
  }) async {
    final prompt = '''
请为涉川 App 用户生成一句个性化的诗词风格签名，用于分享卡片。

用户信息：
- 昵称：$nickname
- 正在挑战：$riverName
- 当前河段：$sectionName
- 进度：${currentKm.toStringAsFixed(0)} / ${totalKm.toStringAsFixed(0)} 公里

要求：
1. 一句简短的古风/诗词风格句子，8-20 字
2. 可融入江河、行走、朝圣等意象
3. 适合作为分享卡底部结语
4. 直接输出签名内容，不要加引号或解释
''';
    final result = await sendAndPoll(
      userId: userId,
      message: prompt,
      createNewConversation: true, // 诗词签名每次新建会话，避免上下文干扰
    );
    return result.answer.trim();
  }
}

class CozeChatResult {
  final String conversationId;
  final String chatId;
  final String answer;
  final Map<String, dynamic>? usage;

  CozeChatResult({
    required this.conversationId,
    required this.chatId,
    required this.answer,
    this.usage,
  });
}

class CozeException implements Exception {
  final String message;
  CozeException(this.message);
  @override
  String toString() => message;
}

/// 解析 Dio 异常为用户可读提示（401 等）
String parseCozeDioError(DioException e) {
  if (e.response?.statusCode == 401) {
    final body = e.response?.data;
    String? cozeMsg;
    if (body is Map<String, dynamic>) {
      cozeMsg = body['msg']?.toString();
    }
    return cozeMsg?.isNotEmpty == true
        ? '认证失败：$cozeMsg。请到 Coze 开放平台 (coze.cn/open) 的「API 授权」中重新生成 Personal Access Token，并确保智能体已发布为 API 服务。'
        : '认证失败（401）：API Token 无效或已过期。请到 Coze 开放平台 (coze.cn/open) 的「API 授权」中重新生成 Personal Access Token，并确保智能体已发布为 API 服务。';
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return '网络超时，请检查网络后重试。';
  }
  if (e.response?.data is Map<String, dynamic>) {
    final msg = (e.response!.data as Map<String, dynamic>)['msg']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
  }
  return e.message ?? e.toString();
}
