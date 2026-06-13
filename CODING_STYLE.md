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
- 统一日志宏（封装 `NSLog`，Release 关闭），禁止裸 `NSLog` 散落。
- 异步回调统一在主线程更新 UI。

### 6. UI
- 优先纯代码 / 约束（Masonry 或原生 AutoLayout）；Storyboard 仅用于启动屏与简单页面。
- ViewController 不写业务逻辑，遵循分层（见 ARCHITECTURE.md）。

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
- 三方依赖统一用 CocoaPods 或 SPM（二选一，定后写入 ARCHITECTURE.md）。
