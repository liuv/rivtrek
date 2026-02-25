// Coze 凭证配置 - 构建时注入，不进入版本库
//
// 构建时通过 --dart-define 或 --dart-define-from-file 注入：
//   fvm flutter build apk --dart-define=COZE_API_TOKEN=pat_xxx --dart-define=COZE_BOT_ID=7610775641889947698
//
// 或使用 dart_defines.json（已加入 .gitignore）：
//   fvm flutter build apk --dart-define-from-file=dart_defines.json
//
// 若未注入，则运行时从 SharedPreferences 读取（开发调试用）。

/// 构建时注入的 API Token，未注入时为空
const String kCozeApiToken = String.fromEnvironment(
  'COZE_API_TOKEN',
  defaultValue: '',
);

/// 构建时注入的 Bot ID，未注入时为空
const String kCozeBotId = String.fromEnvironment(
  'COZE_BOT_ID',
  defaultValue: '',
);

/// 是否已通过构建时注入配置（用户无需在设置中填写）
bool get kCozeBuildTimeConfigured =>
    kCozeApiToken.trim().isNotEmpty && kCozeBotId.trim().isNotEmpty;
