//  IMContactCardView.h
//  个人名片「卡片本体」（240pt 定宽）。独立成 view 是为了让**聊天气泡**与**发送前确认 sheet**
//  1:1 复用同一张卡——确认 sheet 要给用户看的正是收方将看到的那张，两处各画一遍必然漂移。
//  规格见 docs/design/CONTACT_CARD_DESIGN.md §5。

#import <UIKit/UIKit.h>

@class IMContactCard;

NS_ASSUME_NONNULL_BEGIN

/// 卡片定宽（与 IMChatRecordCell 的 240 同族：不随内容伸缩，避免"张三"和"欧阳建国先生"两张卡宽度打架）。
FOUNDATION_EXPORT const CGFloat IMContactCardViewWidth;

@interface IMContactCardView : UIView

/// card：解析后的名片；displayName：**收方本地**显示名（备注 > 快照昵称 > uid），由调用方按 IMRemarkStore 解析。
/// metaText：右下角时间/状态富文本（气泡用；确认 sheet 传 nil 则整块隐藏）。
- (void)configureWithCard:(IMContactCard *)card
              displayName:(nullable NSString *)displayName
                     meta:(nullable NSAttributedString *)metaText;

/// 脏名片（JSON 非法 / 缺 u）降级：把卡片内容整块隐藏，让调用方在其上盖一行灰字。
/// 不这么做的话空头像圈与分隔线仍会绘在降级文案背后（cell 复用时还会残留上一行的头像）。
- (void)configureAsUnparsable;

@end

NS_ASSUME_NONNULL_END
