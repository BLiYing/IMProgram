#!/usr/bin/env bash
# 在「本地源码」与「正式版本」之间切换 IMProgram 用的 im-rtc-ios（IMCallEngine / IMCallKit / IMCallEngineWebRTC）。
#
# 用法（在 IMProgram 仓根目录；切完要重新解析依赖，脚本会顺手做）:
#   ./scripts/switch-rtc-sdk.sh remote [版本]   # 默认档：GitHub 正式版，Exact 版本（默认 2.0.0）
#   ./scripts/switch-rtc-sdk.sh local           # 本地源码：../im-rtc/im-rtc-ios，改 SDK 源码立刻生效
#   ./scripts/switch-rtc-sdk.sh status          # 看当前是哪一档
#
# 原理：只改 IMProgram.xcodeproj/project.pbxproj 里那一个包引用——
#   local  = XCLocalSwiftPackageReference（relativePath），三个 product 不带 package 行；
#   remote = XCRemoteSwiftPackageReference（repositoryURL + exactVersion），三个 product 各带一行 package。
# pbxproj 不能写注释，所以两种形态都由本脚本生成；`local` 的输出与切换前的本地引用逐字一致。
# 切 remote 后 Xcode 会在 xcshareddata/swiftpm/Package.resolved 里记下版本与提交；切 local 不需要它。
# 切档后请**关掉再重开 Xcode 工程**（它缓存了包引用），否则界面里还是旧的一档。
set -euo pipefail

cd "$(dirname "$0")/.."
PBX="IMProgram.xcodeproj/project.pbxproj"
REPO_URL="https://github.com/BLiYing/im-rtc-ios.git"
LOCAL_PATH="../im-rtc/im-rtc-ios"
PKG_ID="8AD0F3F3A92D9C4CFD6B5E29"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ -f "$PBX" ] || { echo "找不到 ${PBX}（请在 IMProgram 仓里运行）" >&2; exit 1; }

current() {
  if grep -q 'isa = XCLocalSwiftPackageReference;' "$PBX"; then echo local
  elif grep -q 'isa = XCRemoteSwiftPackageReference;' "$PBX"; then
    echo "remote $(perl -0ne 'print $1 if /repositoryURL = "[^"]*";\s*requirement = \{\s*kind = exactVersion;\s*version = ([^;]+);/' "$PBX")"
  else echo unknown; fi
}

to_local() {
  LOCAL_PATH="$LOCAL_PATH" PKG_ID="$PKG_ID" perl -0pi -e '
    s/XCRemoteSwiftPackageReference "im-rtc-ios"/XCLocalSwiftPackageReference "im-rtc-ios"/g;
    s/Begin XCRemoteSwiftPackageReference section/Begin XCLocalSwiftPackageReference section/;
    s/End XCRemoteSwiftPackageReference section/End XCLocalSwiftPackageReference section/;
    s/isa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "[^"]*";\n\t\t\trequirement = \{\n\t\t\t\tkind = exactVersion;\n\t\t\t\tversion = [^;]*;\n\t\t\t\};/isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = "$ENV{LOCAL_PATH}";/;
    s/\t\t\tpackage = $ENV{PKG_ID} \/\* XCLocalSwiftPackageReference "im-rtc-ios" \*\/;\n//g;
  ' "$PBX"
}

to_remote() {
  REPO_URL="$REPO_URL" VER="$1" PKG_ID="$PKG_ID" perl -0pi -e '
    s/XCLocalSwiftPackageReference "im-rtc-ios"/XCRemoteSwiftPackageReference "im-rtc-ios"/g;
    s/Begin XCLocalSwiftPackageReference section/Begin XCRemoteSwiftPackageReference section/;
    s/End XCLocalSwiftPackageReference section/End XCRemoteSwiftPackageReference section/;
    s/isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = "[^"]*";/isa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "$ENV{REPO_URL}";\n\t\t\trequirement = {\n\t\t\t\tkind = exactVersion;\n\t\t\t\tversion = $ENV{VER};\n\t\t\t};/;
    s/\t\t\tpackage = $ENV{PKG_ID} [^\n]*\n//g;
    s/(isa = XCSwiftPackageProductDependency;\n)(\t\t\tproductName = (?:IMCallEngineWebRTC|IMCallKit|IMCallEngine);)/$1\t\t\tpackage = $ENV{PKG_ID} \/* XCRemoteSwiftPackageReference "im-rtc-ios" *\/;\n$2/g;
  ' "$PBX"
}

case "${1:-}" in
  status) current ;;
  local)
    to_local
    echo "已切到本地源码：$(current)（${LOCAL_PATH}）。请重开 Xcode 工程。" ;;
  remote)
    ver="${2:-2.0.0}"
    to_remote "$ver"
    echo "已切到正式版：$(current)。解析依赖中…"
    xcodebuild -resolvePackageDependencies -workspace IMProgram.xcworkspace -scheme IMProgram 2>&1 | tail -3
    echo "请重开 Xcode 工程。" ;;
  *) usage ;;
esac
