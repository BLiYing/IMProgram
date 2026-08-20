//  IMChatDateJumpViewController.h
//  会话内「按日期跳转」日历卡片（搜索功能）。呈现形态严格仿 IMFilePickerViewController：
//  UIModalPresentationPageSheet + 自定义 detent + grabber + 自持 IMLiquidNavigationBar（左上 Liquid Glass ✕）。
//  点 📅 从聊天页底部弹出本卡片，选天/最早/今天即回调、dismiss，跳转落在原聊天页（不换页）。
//  设计见 docs/SEARCH_DESIGN.md §5 / §5.1。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 回调类型：选中某天 / 跳最早 / 跳今天。
typedef NS_ENUM(NSInteger, IMDateJumpKind) {
    IMDateJumpKindDate = 0,   ///< 选中具体某天（day 非空）
    IMDateJumpKindEarliest,   ///< 「最早」快捷
    IMDateJumpKindToday,      ///< 「今天」快捷
};

@interface IMChatDateJumpViewController : UIViewController

/// activeDays：本机已同步范围内「有消息的日子」（用设备时区当天 00:00 的 NSDate 归一，供日历打点/限定可选范围）。
/// 可空/空集时不打点、全月可选。onPick：选天/最早/今天回调（day 仅在 kind=Date 时非空，为当天 00:00）。
- (instancetype)initWithActiveDays:(nullable NSSet<NSDate *> *)activeDays
                            onPick:(void (^)(IMDateJumpKind kind, NSDate * _Nullable day))onPick;

- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
