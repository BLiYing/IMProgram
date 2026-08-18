#!/usr/bin/env bash
# check-file-size.sh —— 防巨类体检：单文件行数 + 共享私有头属性数超阈值即失败。
#
#   用法（仓库根目录）：  ./scripts/check-file-size.sh
#   接入：提交前钩子 / CI / xcodebuild 之前调用；退出码 1 = 有文件超预算。
#
# 设计：阈值定得「现在能过、复胖会响」。真正超标的历史欠账登记在 GRANDFATHER，
# 上限=当前行数留少量余量——**只准降不准升**；要动它请拆分，别往里加。降到 MAX 以下后从表里删。
#
# 超标的正确处理是**拆分**，不是放宽阈值：
#   ① 有自己状态+视图的功能 → 独立协作对象（参考 IMChatBannerStack）
#   ② VC 上一组内聚方法    → 分文件 category（+Media/+Menu/…）
#   ③ 纯逻辑（无 self）     → *Logic/*Util 自由函数 + 单测（参考 IMChatMessageLogic）
set -u

MAX_LINES=${MAX_LINES:-1500}          # 未登记 .m 文件行数上限（可用环境变量覆盖，便于调参）
WARN_RATIO=${WARN_RATIO:-80}          # 达上限该比例即预警（不失败），尽早规划拆分
PRIVATE_H_MAX=${PRIVATE_H_MAX:-72}    # 共享类扩展（*+Private.h）@property 条数上限：加属性=加耦合，优先让协作对象自持状态

# 历史欠账（已超 MAX_LINES、待拆分）。值 = 当前行数 + 少量余量。
grandfather_limit() {
  case "$1" in
    *) echo "" ;;
  esac
}

cd "$(dirname "$0")/.." || { echo "无法定位仓库根目录"; exit 2; }

fail=0
warn=0

echo "== 单文件行数体检（默认上限 ${MAX_LINES}；历史欠账见脚本内 GRANDFATHER）=="
while IFS= read -r f; do
  lines=$(wc -l < "$f" | tr -d ' ')
  gf=$(grandfather_limit "$f")
  if [ -n "$gf" ]; then limit=$gf; tag=" [欠账·待拆]"; else limit=$MAX_LINES; tag=""; fi
  if [ "$lines" -gt "$limit" ]; then
    echo "  ✗ FAIL  ${f}  ${lines} 行 > ${limit}${tag}"
    fail=1
  else
    warn_at=$(( limit * WARN_RATIO / 100 ))
    if [ "$lines" -ge "$warn_at" ]; then
      echo "  ⚠ WARN  ${f}  ${lines} 行（≥ ${warn_at}，接近上限 ${limit}）${tag}"
      warn=1
    fi
  fi
done < <(find IMProgram/Modules IMProgram/Common -name "*.m" -not -path "*/build/*" | sort)

echo ""
echo "== 共享私有头属性数体检（上限 ${PRIVATE_H_MAX} 个 @property）=="
while IFS= read -r h; do
  props=$(grep -c "@property" "$h")
  if [ "$props" -gt "$PRIVATE_H_MAX" ]; then
    echo "  ✗ FAIL  ${h}  ${props} 个 @property > ${PRIVATE_H_MAX}"
    echo "         共享类扩展是全类共享的可变状态面；新状态优先归协作对象自持，别堆这里。"
    fail=1
  else
    echo "  ✓ OK    ${h}  ${props} 个 @property"
  fi
done < <(find IMProgram/Modules -name "*+Private.h" | sort)

echo ""
if [ "$fail" -ne 0 ]; then
  echo "结果：✗ 有文件超预算——请拆分（造协作对象 / 分文件 category / 抽纯逻辑），不要放宽阈值。"
  exit 1
fi
[ "$warn" -ne 0 ] && echo "结果：✓ 通过（有 WARN——尽早规划拆分，勿等触顶）。" || echo "结果：✓ 全部通过。"
exit 0
