#!/usr/bin/env bash
# 自动挑模拟器（scripts/test.sh 与 scripts/ui-smoke.sh 共用；source 进来用）。
# 输出一行「udid<TAB>名字<TAB>运行时」；没有可用 iPhone 时返回非 0。
pick_sim() {
    # 同一运行时下的挑选顺序：已经 Booted 的 iPhone > 首选机型（IM_PREFERRED_SIM，默认 iPhone 17 Pro Max）> 列表里第一台。
    # 以前直接取第一台，列表排序让它总落在 iPhone 16e 上，而日常联调 / 截图用的是 17 Pro Max，
    # 结果单测每次都另外拉起一台 16e。
    xcrun simctl list devices available -j | IM_PREFERRED_SIM="${IM_PREFERRED_SIM:-iPhone 17 Pro Max}" python3 -c '
import json, os, sys, re
data = json.load(sys.stdin)["devices"]
preferred = os.environ.get("IM_PREFERRED_SIM", "")
best = None  # (版本, 档位, udid, 名字, 运行时)
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]) or [0])
    picked = None
    for d in devices:
        if not (d.get("isAvailable") and d.get("name", "").startswith("iPhone")):
            continue
        rank = 0 if d.get("state") == "Booted" else 1 if d.get("name") == preferred else 2
        if picked is None or rank < picked[0]:
            picked = (rank, d["udid"], d["name"])
    if picked and (best is None or (ver, -picked[0]) > (best[0], -best[1])):
        best = (ver, picked[0], picked[1], picked[2], runtime.rsplit(".", 1)[-1])
if not best:
    sys.exit(1)
print("%s\t%s\t%s" % (best[2], best[3], best[4]))
'
}
