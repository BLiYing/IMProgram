//  IMContactCells.h
//  通讯录复用 Cell：IMContactCell（头像+名称+副标题+可选动作按钮，好友/搜索结果用）、
//  IMContactRequestCell（额外两枚 同意/拒绝 按钮，"新的朋友"收件区用）。

#import <UIKit/UIKit.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 头像+名称+副标题，右侧可选一枚动作按钮（搜索结果的 加好友/已申请/发消息/同意）。
@interface IMContactCell : UITableViewCell

/// 配置基础信息；subtitle 传 nil 时副标题行隐藏。
- (void)configureWithCard:(IMUserCard *)card subtitle:(nullable NSString *)subtitle;
/// 配置右侧动作按钮：title 为 nil 隐藏；enabled=NO 显示为灰色不可点；点击回调 onAction。
- (void)setActionTitle:(nullable NSString *)title enabled:(BOOL)enabled action:(nullable void (^)(void))onAction;

@end

/// "新的朋友"行：右侧 同意 / 拒绝 两枚按钮。
@interface IMContactRequestCell : UITableViewCell

- (void)configureWithCard:(IMUserCard *)card
                 onAccept:(void (^)(void))onAccept
                 onReject:(void (^)(void))onReject;

@end

NS_ASSUME_NONNULL_END
