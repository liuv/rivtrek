#!/usr/bin/env bash
# 在已连接的小米/Android 手机上打开 Health Connect（系统版 com.android.healthconnect.controller）
# 用法: ./tools/open_health_connect.sh  或  bash tools/open_health_connect.sh

set -e
PKG="com.android.healthconnect.controller"

echo "尝试用系统 Intent 打开 Health Connect..."

# 1) 应用详情页（用单引号避免 shell 吃掉包名）
if adb shell am start -a android.settings.ACTION_APPLICATION_DETAILS_SETTINGS -d 'package:com.android.healthconnect.controller' 2>/dev/null; then
  echo "已打开应用详情页，请点击「打开」进入健康数据共享。"
  exit 0
fi

# 2) 打开「管理健康权限」界面
if adb shell am start -a "android.health.connect.action.MANAGE_HEALTH_PERMISSIONS" 2>/dev/null; then
  echo "已启动: 管理健康权限"
  exit 0
fi

# 2) 部分机型用 androidx 的 action
if adb shell am start -a "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" 2>/dev/null; then
  echo "已启动: Health Connect 权限说明"
  exit 0
fi

# 3) 直接启动主界面（系统版常见入口，小米/Android 14+ 实测可用）
if adb shell am start -n "${PKG}/.navigation.TrampolineActivity" 2>/dev/null; then
  echo "已启动: Health Connect 主界面 (TrampolineActivity)"
  exit 0
fi

# 4) 其他可能的 Activity
for activity in \
  ".migration.MigrationActivity" \
  ".permissions.request.PermissionsActivity" \
  "com.android.healthconnect.controller.MainActivity" \
  ".MainActivity"; do
  if adb shell am start -n "${PKG}/${activity}" 2>/dev/null; then
    echo "已启动: ${PKG}/${activity}"
    exit 0
  fi
done

echo "未找到可用的启动方式。正在列出该包的可启动 Activity..."
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "${PKG}" 2>/dev/null || true
echo ""
echo "列出包内 export 的 Activity："
adb shell dumpsys package "${PKG}" | grep -A 2 "Activity Resolver" || adb shell dumpsys package "${PKG}" | grep "android.intent.action.MAIN" -A 1 || true
echo ""
echo "可手动在「设置 → 应用 → 健康数据共享 / Health Connect」里进入。"
