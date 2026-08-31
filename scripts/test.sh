#!/usr/bin/env bash
#
# IMProgram（iOS）回归的**唯一入口**——与后端 IMServer 的 `./scripts/test.sh` 对称。
# 声明「完成」前跑它，贴输出。
#
# 用法：
#   ./scripts/test.sh                 # 体量门禁 + 编译 + IMProgramTests 单测
#   BUILD_ONLY=1 ./scripts/test.sh    # 只编译（不碰模拟器，最快；日常改代码用这个）
#   ONLY=IMResendPolicyTests ./scripts/test.sh          # 只跑一个测试类
#   ONLY=IMResendPolicyTests/testXxx ./scripts/test.sh  # 只跑一条用例
#   IM_SIM=<udid|名字> ./scripts/test.sh                # 指定模拟器（默认自动挑最新 iOS 的 iPhone）
#
# 为什么要有这个脚本（2026-08-31 加，起因见 current_task.md「iOS 测试为什么慢」）：
# 手拼 xcodebuild 命令行每次都拼得不一样，三个坑反复踩——
#   ① **不能跑整个 scheme**：它带着 IMProgramUITests，`testExample` 一条 135s、`testLaunch` 37s，
#      要真启动 App 跑交互。单测本身 313 条加起来不到 1 分钟，全被这俩拖死。
#      故写死 `-only-testing:IMProgramTests`。要跑 UI 测试请单独手动跑，别塞进本脚本。
#   ② **必须关并行**：Xcode 默认按 target 克隆模拟器并行跑（日志里的 `Clone 1/2 of …`），
#      一台机器上就是自己跟自己抢 CPU，把 `IMMediaPlaceholderTests` 那条时序敏感的用例压出偶发失败
#      （2026-08-30 首次观察，6.2s vs 正常 1.6s；单独重跑必绿）。故写死 `-parallel-testing-enabled NO`。
#   ③ **失败原因不在正文里**：xcodebuild 纯文本日志只给一句 `** TEST FAILED **`，断言原文在 .xcresult 里。
#      故固定 `-resultBundlePath`，失败时用 xcresulttool 把「哪条用例 + 断言原文」直接打出来。
# 另：固定 `-derivedDataPath` 复用增量编译产物（默认 build/DerivedData，已在 .gitignore）。
#
# 退出码非 0 = 有一项没过，可直接当门禁用。

set -euo pipefail
cd "$(dirname "$0")/.."

WORKSPACE="IMProgram.xcworkspace"
SCHEME="IMProgram"
UNIT_TARGET="IMProgramTests"
DERIVED="${IM_DERIVED_DATA:-build/DerivedData}"
RESULT="build/TestResults.xcresult"
LOG="build/xcodebuild-test.log"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
pass() { printf '\033[32m✓ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1"; }

mkdir -p build

# ─────────────────────────────────────────────────────────────
bold "[1/3] 防巨类体检（单文件行数 + 共享私有头属性数，见 CODING_STYLE §7）"
./scripts/check-file-size.sh
pass "体量门禁通过"

# ─────────────────────────────────────────────────────────────
if [ "${BUILD_ONLY:-0}" = "1" ]; then
    bold "[2/3] 编译（BUILD_ONLY=1：跳过模拟器与单测）"
    set +e
    xcodebuild build \
        -workspace "$WORKSPACE" -scheme "$SCHEME" \
        -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" \
        CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$LOG" | grep --line-buffered -E '^(\*\*|.*(error|warning):)'
    # ⚠ 千万别在这条管道尾巴上加 `|| true`：那会把 PIPESTATUS 换成 `true` 的 0，
    # 于是编译/测试失败也报"通过"（2026-08-31 自测抓到——脚本本身就先踩了一次）。
    # `set +e` 已经保证 grep 没匹配到东西时不会中断脚本，不需要 `|| true`。
    status=${PIPESTATUS[0]}
    set -e
    [ "$status" -eq 0 ] || { fail "编译失败，完整日志：$LOG"; exit "$status"; }
    pass "编译通过"
    bold "[3/3] 跳过（BUILD_ONLY）"
    bold "编译通过 ✅（未跑单测——声明「完成」前请去掉 BUILD_ONLY 再跑一次）"
    exit 0
fi

# ─────────────────────────────────────────────────────────────
bold "[2/3] 选模拟器"
# 默认自动挑「可用 iOS 运行时里版本最高的那个」下的第一台 iPhone——写死名字（如 iPhone 17 Pro）
# 会在换 Xcode / 换机器后直接报 destination 找不到，而这类失败看起来像"测试挂了"，很浪费排查时间。
pick_sim() {
    xcrun simctl list devices available -j | python3 -c '
import json, sys, re
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]) or [0])
    for d in devices:
        if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
            if best is None or ver > best[0]:
                best = (ver, d["udid"], d["name"], runtime.rsplit(".", 1)[-1])
            break
if not best:
    sys.exit(1)
print("%s\t%s\t%s" % (best[1], best[2], best[3]))
'
}

if [ -n "${IM_SIM:-}" ]; then
    # 用户显式指定：udid 直接用，名字交给 xcodebuild 自己解析。
    if [[ "$IM_SIM" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
        DESTINATION="platform=iOS Simulator,id=$IM_SIM"
    else
        DESTINATION="platform=iOS Simulator,name=$IM_SIM"
    fi
    echo "  指定模拟器：$IM_SIM"
else
    SIM_INFO="$(pick_sim)" || { fail "找不到可用的 iPhone 模拟器（xcrun simctl list devices available）"; exit 1; }
    SIM_UDID="$(printf '%s' "$SIM_INFO" | cut -f1)"
    SIM_NAME="$(printf '%s' "$SIM_INFO" | cut -f2)"
    SIM_RT="$(printf '%s' "$SIM_INFO" | cut -f3)"
    DESTINATION="platform=iOS Simulator,id=$SIM_UDID"
    echo "  自动选中：$SIM_NAME（$SIM_RT）  $SIM_UDID"
fi
pass "模拟器就绪"

# ─────────────────────────────────────────────────────────────
ONLY_TESTING="$UNIT_TARGET"
[ -n "${ONLY:-}" ] && ONLY_TESTING="$UNIT_TARGET/$ONLY"

bold "[3/3] 单元测试（-only-testing:$ONLY_TESTING，串行）"
rm -rf "$RESULT"   # -resultBundlePath 遇到已存在的路径会直接报错
set +e
xcodebuild test \
    -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -sdk iphonesimulator -destination "$DESTINATION" \
    -only-testing:"$ONLY_TESTING" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$RESULT" \
    CODE_SIGNING_ALLOWED=NO 2>&1 \
  | tee "$LOG" \
  | grep --line-buffered -E "^(Test suite|\*\*)|failed on|error:"
# ⚠ 同上：这里加 `|| true` 会让 PIPESTATUS[0] 变成 `true` 的 0，测试挂了也报"通过"。
status=${PIPESTATUS[0]}
set -e

# 统计与失败明细：断言原文只在 .xcresult 里，纯文本日志给不出。
if [ -d "$RESULT" ]; then
    xcrun xcresulttool get test-results summary --path "$RESULT" --compact 2>/dev/null \
      | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print("\n通过 %s / 共 %s（失败 %s，跳过 %s）" % (
    s.get("passedTests", "?"), s.get("totalTestCount", "?"),
    s.get("failedTests", "?"), s.get("skippedTests", "?")))
fails = s.get("testFailures") or []
if isinstance(fails, dict):
    fails = [fails]
for f in fails:
    print("\n  ✗ %s / %s" % (f.get("targetName", "?"), f.get("testName", "?")))
    msg = (f.get("failureText") or "").strip()
    for line in msg.splitlines()[:6]:
        print("      " + line)
' || true
fi

if [ "$status" -ne 0 ]; then
    fail "测试未通过（完整日志：$LOG；结果包：$RESULT）"
    echo "  失败某一条时，先单独重跑那个类确认是不是偶发："
    echo "    ONLY=<TestClass> ./scripts/test.sh"
    echo "  已知偶发项见 current_task.md「已知坑」：IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48"
    exit "$status"
fi

pass "单测通过"
bold "全量通过 ✅"
