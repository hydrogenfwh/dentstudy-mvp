#!/usr/bin/env bash
# Usage: bash mobile/release.sh check|android|ios
# Builds locally only. Does not upload, register an app, or create credentials.
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-check}"
case "$target" in
  check|android|ios) ;;
  *) echo '用法：bash mobile/release.sh check|android|ios' >&2; exit 2 ;;
esac

flutter_bin="${FLUTTER_BIN:-}"
if [[ -z "$flutter_bin" ]]; then
  if [[ -x ../tools/flutter/bin/flutter ]]; then
    flutter_bin="../tools/flutter/bin/flutter"
  else
    flutter_bin="$(command -v flutter || true)"
  fi
fi

missing=0
require() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "可用：$label"
  else
    echo "待准备：$label"
    missing=$((missing + 1))
  fi
}
require 'Flutter SDK' test -x "$flutter_bin"

if [[ "$target" == check || "$target" == android ]]; then
  sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk_dir" && -f android/local.properties ]]; then
    sdk_dir="$(sed -n 's/^sdk.dir=//p' android/local.properties | head -n 1)"
  fi
  sdk_dir="${sdk_dir:-$HOME/Library/Android/sdk}"
  java_bin="java"
  if [[ -n "${JAVA_HOME:-}" ]]; then
    java_bin="$JAVA_HOME/bin/java"
  elif [[ -x '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java' ]]; then
    export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
    java_bin="$JAVA_HOME/bin/java"
  fi
  require 'Java（项目需要 JDK 17 或更高版本）' "$java_bin" -version
  require 'Android SDK platform-tools' test -x "$sdk_dir/platform-tools/adb"
  require 'Android SDK platforms' test -d "$sdk_dir/platforms"
  require 'Android SDK build-tools' test -d "$sdk_dir/build-tools"
  require '上传密钥配置 android/key.properties（内容由 Gradle 校验）' test -f android/key.properties
fi

if [[ "$target" == check || "$target" == ios ]]; then
  require '完整 Xcode' xcodebuild -version
  require 'CocoaPods' pod --version
  if ! /usr/bin/grep -Eq 'DEVELOPMENT_TEAM = [A-Z0-9]{10};' ios/Runner.xcodeproj/project.pbxproj; then
    echo '待准备：在 Xcode 的 Runner → Signing & Capabilities 中选择 Apple Developer Team'
    missing=$((missing + 1))
  else
    echo '已配置：Apple Developer Team（证书和签名在构建时验证）'
  fi
fi

if [[ "$missing" -gt 0 ]]; then
  echo "尚有 $missing 项环境/签名条件待准备；未开始构建。"
  exit 1
fi
if [[ "$target" == check ]]; then
  echo '基础环境检查通过；SDK 许可、证书有效性与实机运行仍由正式构建和测试验证。'
  exit 0
fi

app_version="$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' pubspec.yaml | head -n 1)"
build_time="$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M 北京时间')"
args=(--release '--dart-define=API_URL=https://dentstudy.uno/api'
  '--dart-define=QUESTION_BANK_ASSET=assets/all_questions.json'
  "--dart-define=APP_VERSION=$app_version" "--dart-define=BUILD_TIME=$build_time")
if [[ "$target" == android ]]; then
  "$flutter_bin" build appbundle "${args[@]}"
  echo '产物：mobile/build/app/outputs/bundle/release/app-release.aab'
else
  "$flutter_bin" build ipa "${args[@]}"
  echo '产物目录：mobile/build/ios/ipa/'
fi
