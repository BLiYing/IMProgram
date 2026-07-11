# IMProgram — 项目说明（供 Codex 读取）

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
- 架构设计见 `ARCHITECTURE.md`；通信协议见 `../IMServer/docs/PROTOCOL.md`。
- 提交信息格式：`类型(模块): 描述`。

## 工作流程与「完成的定义」（每次自动遵循，无需用户重复提醒）
动手前（Read，不靠记忆）：
- 改客户端代码前，先 Read `CODING_STYLE.md` 与 `ARCHITECTURE.md`；涉及协议字段再 Read `../IMServer/docs/PROTOCOL.md`。

声明「完成」前必须全部满足，并在回复中**贴出编译输出**：
1. 新功能配套测试用例（`IMProgramTests/` 的 XCTest），纳入回归。
2. 真编译（已引入 CocoaPods，**用 `.xcworkspace`**）：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 通过（零 error/warning）。
3. 测试 bundle 编译：`xcodebuild build-for-testing -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` → `** TEST BUILD SUCCEEDED **`。
   - **不强制启动模拟器执行**（本机模拟器子系统不稳，常 launchd_sim 卡死）。XCTest 由用户在真机/Xcode 手动跑。
4. 更新 `current_task.md`。
5. **更新 `../IMServer/docs/CLIENT_PARITY.md` 对应单元格**（功能×端状态的唯一来源）。
6. **端对齐扫一遍**：凡声明"某功能完成/对齐 Web"，先按 CLIENT_PARITY **逐行 diff iOS↔Web**——Web ✅ 而 iOS ⬜ 的就是缺口，要么补上、要么在回复里点名为已知缺口。（"↓N 跳转"曾因没做这步而漏掉。）
7. **给出真机验证清单**：列出本次需在真机上肉眼确认的功能点，交用户手测；明确说清「没做什么 / 已知限制 / TODO」，不假装完成。

主动建议（不必用户开口）：
- 完成较大功能后，建议跑 `/code-review` 自审找 bug。
- 触及鉴权 / 加密 / E2E / 敏感数据时，建议跑 `/security-review`。

## 构建 / 测试
- **已用 CocoaPods（FMDB）**：打开/构建一律用 `IMProgram.xcworkspace`，不再用 `.xcodeproj`。新机器先 `cd IMProgram && pod install`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译：`xcodebuild build-for-testing -workspace IMProgram.xcworkspace -scheme IMProgram ... CODE_SIGNING_ALLOWED=NO`（执行由真机/Xcode 手动跑）
- Podfile 已关 `ENABLE_USER_SCRIPT_SANDBOXING`（post_install），避免 Pods 资源拷贝被沙盒拒写。
