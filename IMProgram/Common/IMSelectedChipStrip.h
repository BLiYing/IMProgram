//  IMSelectedChipStrip.h
//  「已选成员」横向头像条：一格 = 44pt 头像圈 + 11pt 名字 + 右上角 ✕（点 ✕ 回调 onRemove）。
//
//  从建群第二步（IMGroupCreateViewController 的成员横条）抽出来的公共件：
//  建群页成员回显与分享选择页底部已选栏（SHARE_PICKER_UX_SKETCH ④）共用，两处长得一样、删法一样。
//  用 frame 直接摆格子：这是一条会整体重建的横向条，上 Auto Layout 只是给约束求解器添活。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 一格的数据。chipID 是回调 onRemove 时交回的键（建群页 = uid，分享页 = conv_id）。
@interface IMSelectedChip : NSObject
@property (nonatomic, copy) NSString *chipID;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, copy) NSString *seed;   ///< 无头像时首字母圈的配色种子
@property (nonatomic, copy) NSString *name;
+ (instancetype)chipWithID:(NSString *)chipID avatarURL:(nullable NSString *)avatarURL
                      seed:(NSString *)seed name:(NSString *)name;
@end

@interface IMSelectedChipStrip : UIScrollView

/// 一格宽 / 高（头像 44 + 名字），调用方据此给容器定高。
@property (class, nonatomic, readonly) CGFloat chipWidth;
@property (class, nonatomic, readonly) CGFloat chipHeight;

/// 最多画多少格（0 = 不限）；超出部分显示「+N」。建群页勾了几百人时不逐个建视图。
@property (nonatomic, assign) NSUInteger maxChips;
/// 首格左边距（默认 space4，与卡片左边距对齐）。
@property (nonatomic, assign) CGFloat leadingInset;
/// 格子顶边距（默认 12）。
@property (nonatomic, assign) CGFloat chipTop;
/// 点某格的 ✕。
@property (nonatomic, copy, nullable) void (^onRemove)(NSString *chipID);

/// 整条重建。scrollToEnd=YES 时滚到最右（新勾选的人出现在末尾，让用户看见它进来了）。
- (void)setChips:(NSArray<IMSelectedChip *> *)chips scrollToEnd:(BOOL)scrollToEnd;

/// 单独造一格（origin 为左上角）。onRemove 为 nil 时不画 ✕。分享确认面板的网格用它。
+ (UIView *)chipViewForChip:(IMSelectedChip *)chip origin:(CGPoint)origin
                    onRemove:(nullable void (^)(NSString *chipID))onRemove;

/// 「＋ 添加」格（建群页固定在条右侧那一列用）。circle 回传那个圆，供深浅色切换时重刷 CGColor 描边。
+ (UIView *)addChipWithTitle:(NSString *)title target:(id)target action:(SEL)action
                      circle:(UILabel *_Nullable *_Nullable)circle;

@end

NS_ASSUME_NONNULL_END
