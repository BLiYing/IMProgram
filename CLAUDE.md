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
- 遵循 `CODING_STYLE.md`：类前缀 `IM`、4 空格缩进、网络/IO 必须有错误恢复。
- 架构设计见 `ARCHITECTURE.md`；通信协议见 `../IMServer/docs/PROTOCOL.md`。
- 提交信息格式：`类型(模块): 描述`。

## 工作流程与「完成的定义」（每次自动遵循，无需用户重复提醒）
动手前（Read，不靠记忆）：
- 改客户端代码前，先 Read `CODING_STYLE.md` 与 `ARCHITECTURE.md`；涉及协议字段再 Read `../IMServer/docs/PROTOCOL.md`。

声明「完成」前必须全部满足，并在回复中**贴出编译输出**：
1. 新功能配套测试用例（`IMProgramTests/` 的 XCTest），纳入回归。
2. 真编译：`xcodebuild -project IMProgram.xcodeproj -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 通过（零 error/warning）。
3. 测试 bundle 编译：`xcodebuild build-for-testing -project IMProgram.xcodeproj -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` → `** TEST BUILD SUCCEEDED **`。
   - **不强制启动模拟器执行**（本机模拟器子系统不稳，常 launchd_sim 卡死）。XCTest 由用户在真机/Xcode 手动跑。
4. 更新 `current_task.md`。
5. **给出真机验证清单**：列出本次需在真机上肉眼确认的功能点，交用户手测；明确说清「没做什么 / 已知限制 / TODO」，不假装完成。

主动建议（不必用户开口）：
- 完成较大功能后，建议跑 `/code-review` 自审找 bug。
- 触及鉴权 / 加密 / E2E / 敏感数据时，建议跑 `/security-review`。

## 构建 / 测试
- 构建：`xcodebuild -project IMProgram.xcodeproj -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译：`xcodebuild build-for-testing ... CODE_SIGNING_ALLOWED=NO`（执行由真机/Xcode 手动跑，见上「完成的定义」）
