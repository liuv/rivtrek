/// 分享卡片底部结语：可在此配置默认选项，用户可在分享预览中任选其一或自定义一句。
const List<String> kShareClosingPhraseOptions = [
  '步履不停 丈量江山',
  '步步烟波 念念相续',
  '向心而行 面己朝圣',
  '涉山涉水 静心静气',
];

/// 默认选中的结语（取列表第一项）
String get kShareClosingPhraseDefault =>
    kShareClosingPhraseOptions.isNotEmpty ? kShareClosingPhraseOptions.first : '步履不停 丈量江山';
