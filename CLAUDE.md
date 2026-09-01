# IMProgram — 项目说明（供 Claude 读取）

## 项目简介
iOS 即时通讯（IM）聊天 App。标准 Xcode 工程，UIKit + Storyboard。

## 技术栈
- 主语言：**Objective-C**（ARC）
- 备用：Swift（新模块/混编，通过 Bridging Header）
- UI：UIKit，纯代码约束为主，Storyboard 仅启动屏/简单页
- 依赖管理：待定（CocoaPods 或 SPM）
- 通信方案：待定（自建 WebSocket / 三方 IM SDK）

## 工程结构
- `IMProgram/` — 主工程源码
- `IMProgramTests/` — 单元测试
- `IMProgramUITests/` — UI 测试
- `IMProgram.xcodeproj` — 工程文件

## 工作约定
- **每次开始主要回复前，先读 `current_task.md` 恢复上下文**，改动后更新它。
- **`current_task.md` 是"活快照"，不是流水账**：固定四节（当前焦点 / 下一步 / 已知坑·限制 / 关联工程·常用命令），**就地覆盖，禁止往下追加 `Status ②③④…` 新块**。需要留痕的历史交给 `git log` 与 `current_task.archive.md`（只读归档）。逐功能×端状态一律只写 `../IMServer/docs/CLIENT_PARITY.md`（唯一来源），别处不复述 ✅。
- 遵循 `CODING_STYLE.md`：类前缀 `IM`、4 空格缩进、网络/IO 必须有错误恢复。
- **新增或修改任何 UI 前必须读取 `docs/UI_COLOR.md`**；颜色/字号/圆角使用 `IMTheme`，
  用户外观偏好使用 `IMAppearance`，禁止业务页面直接持久化外观或新增魔法颜色。
- 架构设计见 `ARCHITECTURE.md`；通信协议见 `../IMServer/docs/PROTOCOL.md`。
- 日志实现见 `docs/LOGGING.md`，跨端共同契约见 `../IMServer/docs/LOGGING.md`；新增日志必须走 `IMLog.h`。
- **今后新增的业务/技术 Markdown 文档一律放入 `docs/`**。根目录仅保留 README、AGENTS/CLAUDE、`current_task.md` 及既有工程入口规范；不为整理目录而移动这些入口文件。
- 提交信息格式：`类型(模块): 描述`。

## 工作流程与「完成的定义」（每次自动遵循，无需用户重复提醒）
动手前（Read，不靠记忆）：
- 改客户端代码前，先 Read `CODING_STYLE.md` 与 `ARCHITECTURE.md`；涉及协议字段再 Read `../IMServer/docs/PROTOCOL.md`。

声明「完成」前必须全部满足，并在回复中**贴出 `./scripts/test.sh` 的输出**：
1. 新功能配套测试用例（`IMProgramTests/` 的 XCTest），纳入回归。
2. **`./scripts/test.sh` 全绿**（体量门禁 + 编译 + `IMProgramTests` 单测）——**这是唯一入口，别手拼 xcodebuild 命令行**，理由见「构建 / 测试」一节。
   - 改代码途中想快速过一遍编译：`BUILD_ONLY=1 ./scripts/test.sh`（不碰模拟器）。但**声明「完成」前必须去掉 `BUILD_ONLY` 再跑一次**。
   - 只跑某个类/某条用例：`ONLY=IMResendPolicyTests ./scripts/test.sh` / `ONLY=IMResendPolicyTests/testXxx ./scripts/test.sh`。
4. 更新 `current_task.md`。
5. **更新 `../IMServer/docs/CLIENT_PARITY.md` 对应单元格**（功能×端状态的唯一来源）。
6. **端对齐扫一遍**：凡声明"某功能完成/对齐 Web"，先按 CLIENT_PARITY **逐行 diff iOS↔Web**——Web ✅ 而 iOS ⬜ 的就是缺口，要么补上、要么在回复里点名为已知缺口。（"↓N 跳转"曾因没做这步而漏掉。）
7. **给出真机验证清单**：列出本次需在真机上肉眼确认的功能点，交用户手测；明确说清「没做什么 / 已知限制 / TODO」，不假装完成。

主动建议（不必用户开口）：
- 完成较大功能后，建议跑 `/code-review` 自审找 bug。
- 触及鉴权 / 加密 / E2E / 敏感数据时，建议跑 `/security-review`。

## 构建 / 测试
- **已用 CocoaPods（FMDB）**：打开/构建一律用 `IMProgram.xcworkspace`，不再用 `.xcodeproj`。新机器先 `cd IMProgram && pod install`。
- **唯一入口：`./scripts/test.sh`**（与后端 `IMServer/scripts/test.sh` 对称）。
  ```bash
  ./scripts/test.sh                            # 体量门禁 + 编译 + IMProgramTests 单测
  BUILD_ONLY=1 ./scripts/test.sh               # 只编译（不碰模拟器，最快）
  ONLY=IMResendPolicyTests ./scripts/test.sh   # 只跑一个类（排查偶发失败用）
  ```
- **不要手拼 `xcodebuild` 命令行**——2026-08-31 之前每次都拼得不一样，反复踩三个坑，脚本已把它们写死：
  1. **不能跑整个 scheme**：它带着 `IMProgramUITests`，`testExample` 一条 135s、`testLaunch` 37s（要真启动 App 跑交互）；而 313 条单测加起来不到 1 分钟。脚本写死 `-only-testing:IMProgramTests`。UI 测试要跑请单独手动跑。
  2. **必须关并行**：Xcode 默认按 target 克隆模拟器并行跑，一台机器上自己跟自己抢 CPU，会把时序敏感的用例压出偶发失败（`IMMediaPlaceholderTests` 那条，见 `current_task.md`「已知坑」）。脚本写死 `-parallel-testing-enabled NO`。
  3. **失败原因不在纯文本日志里**：xcodebuild 只给一句 `** TEST FAILED **`，断言原文在 `.xcresult` 里。脚本固定 `-resultBundlePath` 并用 `xcresulttool` 把「哪条用例 + 断言原文」直接打出来。
  - 另：固定 `-derivedDataPath build/DerivedData` 复用增量产物；模拟器**自动挑**最新 iOS 的 iPhone（写死名字会在换 Xcode/换机后报 destination 找不到，那种失败看起来像"测试挂了"，白费排查时间）。要指定：`IM_SIM=<udid|名字>`。
- 完整日志与结果包落在 `build/`（已 gitignore），**按跑次带 PID**：
  `build/xcodebuild-test.<pid>.log` / `build/TestResults.<pid>.xcresult`；
  `build/xcodebuild-test.log` 与 `build/TestResults.xcresult` 是指向最近一次的软链。
  带 PID 是因为**本脚本会被并发跑起来**（同时开两个会话就够了），共用固定路径时后起的那个
  会删掉前一个正在写的结果包 —— 表现是「全绿却报 TEST FAILED」。脚本每次启动会清掉
  **已退出**跑次的产物（正在跑的另一个会话原样保留）。
  DerivedData 仍是共享的（增量编译产物，Xcode 自己加锁排队）；**模拟器也是共享的**，
  真要并发请 `IM_SIM=<另一台 udid>` 各跑各的。
- Podfile 已关 `ENABLE_USER_SCRIPT_SANDBOXING`（post_install），避免 Pods 资源拷贝被沙盒拒写。
