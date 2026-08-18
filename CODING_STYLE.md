# IMProgram 代码规范（Objective-C 主 / Swift 备）

> 主语言：**Objective-C**。Swift 仅在新模块或混编时使用，规范见下半部分。
> 总原则：可读性 > 取巧；与现有代码风格保持一致；一个文件/方法只做一件事。

---

## 一、Objective-C 规范

### 1. 命名
- **类名**：大驼峰 + 业务前缀，统一前缀 `IM`（避免与系统/三方冲突）。
  例：`IMChatViewController`、`IMMessageModel`、`IMSocketManager`。
- **方法/变量**：小驼峰，语义完整不缩写。`sendMessage:toUser:` 而非 `send:to:`。
- **成员变量**：下划线前缀 `_messageList`，通过 `@property` 暴露访问。
- **常量**：`k` 前缀或全大写宏。`static NSString * const kIMServerHost = @"...";`。
- **通知名 / Key**：集中定义为常量，禁止散落字符串字面量。
- **Bool 方法**：以 `is/has/should` 开头，如 `isConnected`。

### 2. 文件组织
- 一个类一对 `.h/.m`。`.h` 只暴露必要接口，私有方法/属性放 `.m` 的 class extension。
- 引用顺序：系统框架 → 三方库 → 本项目头文件，各组间空行。
- `.h` 中优先用 `@class` 前向声明，减少头文件依赖。

### 3. 属性 / 内存
- 全程 **ARC**。
- 对象默认 `strong`，delegate/block 回调持有方用 `weak`，基本类型用 `assign`，字符串/可变拷贝语义用 `copy`。
- block 内引用 self 用 `__weak typeof(self) weakSelf = self;`，必要时再 `__strong` 强引用，防循环引用。

### 4. 代码风格
- 缩进 4 空格，不用 Tab。大括号 `{` 不换行（K&R）。
- 判空优先 `if (!obj)`；`nil` 安全调用是 OC 特性，但关键路径仍要显式判空。
- 禁止魔法数字/字符串，抽成常量。
- 单方法尽量 < 40 行；超长拆分。

### 5. 错误处理与日志
- 所有 **网络 / IO / 数据库** 调用必须有明确错误恢复分支，不允许吞掉 `NSError`。
- 完整日志规则见 `docs/LOGGING.md`，跨端 Request ID/字段/隐私契约见 `../IMServer/docs/LOGGING.md`。
- 日志统一通过 `IMLog.h`（底层 CocoaLumberjack），禁止业务代码直接调用 `NSLog` 或 `DDLog*`。
  自查：`grep -rn "NSLog(" IMProgram --include="*.m" --include="*.h"` 应为 0 条。
  （2026-08-05 全量复查：本端 0 处违规；后端 Go 曾因有兼容桥接兜底而累计 54 处未被发现，
  详见 `../IMServer/docs/LOGGING.md` §7.1。）
- 按模块使用稳定 tag：`IM.APP` / `IM.HTTP` / `IM.WS` / `IM.DB` / `IM.UI`；HTTP 请求另带唯一 `req=<X-Request-ID>`，请求与响应必须使用同一 ID。
- HTTP 日志必须先脱敏 password/token/authorization/cookie/phone/secret 等字段；multipart/binary 只记元数据，单条正文最多 16 KB。
- Debug 可记录脱敏后的业务正文；Release 对消息正文等业务内容及非 JSON 正文做隐藏，不允许为排障临时绕过脱敏。
- 异步回调统一在主线程更新 UI。

### 6. UI
- 优先纯代码 / 约束（Masonry 或原生 AutoLayout）；Storyboard 仅用于启动屏与简单页面。
- ViewController 不写业务逻辑，遵循分层（见 ARCHITECTURE.md）。
- 新增或修改 UI 前必须读取 `docs/UI_COLOR.md`；使用 `IMTheme` 语义令牌与
  `IMAppearance` 外观设置，禁止业务页面散落固定 RGB/Hex。

### 7. 防巨类（类 / 文件不膨胀）
`IMChatViewController` 曾长到 4718 行、60+ 编译告警才被发现（2026-08 拆分）。**分文件 category 只缩小
「文件」、不缩小「类」**——类还是一个类、`+Private.h` 里仍挂着一堆共享可变属性，是耦合与复胖的根源。
新代码往哪放，按此决策树，别默认往 VC 堆：

- **① 有自己状态 + 视图 / 独立生命周期的功能 → 造独立协作对象**（参考 `IMChatBannerStack`：自带视图+
  布局+持久化，VC 只持一个属性 + 一个 delegate）。判据：需要 **≥2 个新属性**、或有自己的一组视图、
  或有定时器/订阅/缓存。**语音消息等新功能一律走这条**，别做成 VC 上又一批 `@property` + 十几个方法。
- **② VC 上一组内聚方法 → 放对应分文件 category**（`+Media`/`+Menu`/`+DataSource`/…），跨 TU 私有方法
  在 `IMChatViewController+Private.h` 登记；**别新开「杂项」category**。
- **③ 纯逻辑（无 self）→ `*Logic`/`*Util` 自由函数 + 配单测**（参考 `IMChatMessageLogic`、`IMMediaUtil`）。

**红线（机械护栏，别靠自觉）**：`./scripts/check-file-size.sh`——单 `.m` > 1500 行、或 `*+Private.h`
> 72 个 `@property` 即非零退出。**新增属性到共享类扩展 = 警报**，先问「这状态能不能归给某个协作对象自持」。
超标的正确处理是**拆分**（按上面三档），**不是放宽阈值**。历史欠账（`IMChatDetailViewController.m`
2439 行等）在脚本里登记「只准降不准升」，逐步拆到 1500 以下。同样的病别的大页也有（详情页/会话列表/
资料页），红线覆盖整个 `Modules/`，一处触发就顺手治，别等长成第二个 4700 行。

---

## 二、Swift 规范（混编/新模块）

### 1. 命名
- 类型大驼峰，方法/变量小驼峰；不加 `IM` 前缀（Swift 有命名空间）。
- 暴露给 OC 的类用 `@objc` 并加 `IM` 前缀或 `@objc(IMXxx)` 重命名。

### 2. 安全与可选值
- 优先 `let`，需要可变才用 `var`。
- 禁止滥用强解包 `!`；用 `guard let` / `if let` / `??`。
- 模型优先 `struct`，引用语义/需继承才用 `class`。

### 3. 并发与错误
- 异步优先 `async/await`，避免回调地狱。
- 错误用 `throws` + `do/catch`，网络/IO 必须处理失败分支。

### 4. 混编约定
- OC ↔ Swift 通过 `IMProgram-Bridging-Header.h`（OC 暴露给 Swift）与自动生成的 `IMProgram-Swift.h`（Swift 暴露给 OC）。
- 跨语言传递的模型尽量用 OC 类或 `@objc` 兼容类型。

---

## 三、通用约定
- 提交信息：`类型(模块): 描述`，如 `feat(chat): 增加消息已读回执`。
- 每个非平凡改动后更新 `current_task.md`。
- 今后新增业务/技术 Markdown 文档统一放入 `docs/`；README、工程指令、`current_task.md` 和既有入口规范保留根目录。
- 三方依赖统一用 CocoaPods 或 SPM（二选一，定后写入 ARCHITECTURE.md）。
