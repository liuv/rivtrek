/// 与江川向导（Coze）交互的场景，用于按场景组装上传的上下文内容。
/// 新增场景时在此扩展，并在 [RiverGuideProvider.buildLocationContext] 中补充对应逻辑。
enum CozeContextMode {
  /// 江川向导对话：完整上下文（含最近三天步数/里程），便于回答「今天走了多少」等
  chat,

  /// 首页此地风土一次性介绍：仅位置相关，不传最近三天
  locationIntro,

  /// 分享页诗词签名：当前由 [CozeService.generatePoeticSignature] 独立组包，此处预留
  poeticSignature,

  /// 今日总结等，后续扩展（可传三天 + 当日位置）
  dailySummary,
}

extension CozeContextModeExtension on CozeContextMode {
  /// 是否在上下文中包含「最近三天步数/里程」
  bool get includeRecentThreeDays {
    switch (this) {
      case CozeContextMode.chat:
      case CozeContextMode.dailySummary:
        return true;
      case CozeContextMode.locationIntro:
      case CozeContextMode.poeticSignature:
        return false;
    }
  }
}
