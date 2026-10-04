//  IMChatWindowTrim.h
//  聊天窗口超出内存上限时「该丢几条」的判据（从 IMChatViewController+Window 抽出的纯函数）。
//
//  **iOS 独有，没有 im-web 对应物**：两端窗口取舍不同且刻意——iOS 限请求也限内存，Web 只限 DOM
//  （见 IMChatWindowPlan.h 与 MESSAGE_WINDOW_DESIGN.md）。别为了「两端函数一一对应」去 Web 补一个。
//
//  这两条判据错得**很安静**：丢多了 / 丢到锚点身上 → 保位失去参照物、画面跳一下；
//  丢到待发件 → 用户刚发的消息从屏幕上消失；seen 集与 messages 不同步 → 之后到的同一条被当重复吞掉
//  （表现是「窗口末尾莫名少几条」）。调用方负责把 seenConvSeqs 与数组一起改，这里只回答「丢几条」。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/**
 从窗口**尾部**丢几条（向上翻页时用：内容加在顶部，尾部在视口下方，丢掉不影响用户在看的位置）。

 `messages` 是窗口内全部行（显示序）；`cap` 是内存上限；`anchorRow` 是保位参照行
 （NSNotFound = 没有参照）。规则：
  · 超出 `cap` 的部分才丢（count<=cap 返回 0）；
  · **只丢已上号的行**：尾部碰到 conv_seq<=0（待发/失败的本地消息，属于「最新一段」）就停，哪怕还没丢够；
  · 不丢到锚点身上：再丢一条就会让尾部行号 <= anchorRow 时停——丢了它保位就没有参照物。
 */
extern NSInteger IMChatTailDropCount(NSArray<IMMessageModel *> *messages, NSInteger cap, NSInteger anchorRow);

/**
 从窗口**头部**丢几条（向下翻页时用：内容加在底部，头部在视口上方）。

 超出 `cap` 的部分全丢；但 `anchorRow` 落在要丢的那一段里（用户滚太快、视口已越过它）就**一条都不丢**——
 宁可这一轮窗口超标，也不能把用户正看着的行删掉，下一次翻页还会再来一次。anchorRow=NSNotFound 表示无参照。
 */
extern NSInteger IMChatHeadDropCount(NSInteger count, NSInteger cap, NSInteger anchorRow);

NS_ASSUME_NONNULL_END
