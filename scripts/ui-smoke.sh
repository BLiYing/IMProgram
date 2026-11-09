#!/usr/bin/env bash
#
# 移动端冒烟（T3，../IMServer/docs/design/E2E_REGRESSION_DESIGN.md §6）：装上新包后在模拟器里把核心链路走一遍。
#   ① 服务端造数据：固定对端 smokepeer 给设备账号发一条带时间戳的 ping（../IMServer/scripts/smoke/mobile-smoke.mjs）
#   ② UI 测试 IMProgramUITests/IMSmokeUITests：会话列表收到 ping → 点进去 → 发 pong → 气泡出现
#   ③ 回到服务端核对：对端真的收到了 pong
# 连的是开发后端（模拟器里 App 配的地址，默认 127.0.0.1:8080），先 `cd ../IMServer && ./scripts/dev.sh --no-tail`。
#
# 用法：
#   ./scripts/ui-smoke.sh                     # 设备账号默认 user1001
#   SMOKE_USER=user1002 ./scripts/ui-smoke.sh
#   IM_SIM=<udid|名字> ./scripts/ui-smoke.sh   # 指定模拟器（默认同 test.sh 自动挑）
set -euo pipefail
cd "$(dirname "$0")/.."

SMOKE_USER="${SMOKE_USER:-user1001}"
SEED="../IMServer/scripts/smoke/mobile-smoke.mjs"
RESULT="build/UISmoke.$$.xcresult"
LOG="build/ui-smoke.$$.log"
mkdir -p build

source scripts/sim-pick.sh
if [ -n "${IM_SIM:-}" ]; then
    if [[ "$IM_SIM" =~ ^[0-9A-Fa-f-]{36}$ ]]; then DESTINATION="platform=iOS Simulator,id=$IM_SIM"; else DESTINATION="platform=iOS Simulator,name=$IM_SIM"; fi
else
    SIM_INFO="$(pick_sim)" || { echo "✗ 找不到可用的 iPhone 模拟器"; exit 1; }
    DESTINATION="platform=iOS Simulator,id=$(printf '%s' "$SIM_INFO" | cut -f1)"
    echo "模拟器：$(printf '%s' "$SIM_INFO" | cut -f2)"
fi

echo "[1/3] 造数据（对端 smokepeer → ${SMOKE_USER}）"
SEEDED="$(node "$SEED" seed "$SMOKE_USER")"
PEER="$(printf '%s' "$SEEDED" | python3 -c 'import json,sys;print(json.load(sys.stdin)["peer"])')"
PING="$(printf '%s' "$SEEDED" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ping"])')"
PONG="$(printf '%s' "$SEEDED" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pong"])')"
echo "  ping：${PING}"

echo "[2/3] 模拟器 UI 冒烟（IMSmokeUITests）"
set +e
TEST_RUNNER_IM_SMOKE=1 TEST_RUNNER_IM_SMOKE_USER="$SMOKE_USER" TEST_RUNNER_IM_SMOKE_PEER="$PEER" \
TEST_RUNNER_IM_SMOKE_PING="$PING" TEST_RUNNER_IM_SMOKE_PONG="$PONG" \
xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination "$DESTINATION" \
    -only-testing:IMProgramUITests/IMSmokeUITests -parallel-testing-enabled NO \
    -derivedDataPath build/DerivedData -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1
status=$?
set -e
grep -E "Test Case .*(passed|failed|skipped)|error: -" "$LOG" | tail -5 || true
if [ $status -ne 0 ]; then
    xcrun xcresulttool get test-results summary --path "$RESULT" --compact 2>/dev/null | python3 -c '
import json,sys
s=json.load(sys.stdin); f=s.get("testFailures") or []
f=[f] if isinstance(f,dict) else f
for x in f: print("  ✗", x.get("testName"), (x.get("failureText") or "").strip().splitlines()[:3])' || true
    echo "✗ UI 冒烟失败（日志 $LOG，截图在结果包 $RESULT）"; exit 1
fi

echo "[3/3] 服务端核对"
node "$SEED" verify "$SMOKE_USER" "$PONG"
echo "✅ iOS 冒烟通过"
