//  IMEntryCell.h
//  列表首行「入口行」（添加例外 / 搜索成员 / 添加成员 / 添加管理员 / 满员提示 / 加载更多）。
//  规格：LIST_ENTRY_ROW_DESIGN §2 —— 槽 40（图标水平垂直居中，槽左缘 = 头像左缘）+ 间距 12 + 文字，
//  左边距 16，文字左缘 68，separatorInset.left = 68；行高 ≥ 56。自绘约束，不借 UITableViewCell.imageView。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat IMEntryCellSlotWidth;    ///< 图标槽宽 40（= 头像宽）
FOUNDATION_EXPORT const CGFloat IMEntryCellTextLeading;  ///< 文字左缘 68（含左边距 16 + 槽 40 + 间距 12）
FOUNDATION_EXPORT const CGFloat IMEntryCellMinHeight;    ///< 行高下限 56

@interface IMEntryCell : UITableViewCell

@property (nonatomic, readonly) UIView *slotView;        ///< 40pt 宽图标槽
@property (nonatomic, readonly) UIView *iconView;        ///< 槽内居中的图标（线性 SF Symbol 或「＋」圆）
@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly) UILabel *detailLabel;    ///< 满员提示的多行副文案；无副文案时隐藏

/// 无底板线性图标行（22pt）。titleColor / iconTint 传 nil = IMTheme.accent。
- (void)configureWithSymbol:(NSString *)symbolName
                      title:(NSString *)title
                 titleColor:(nullable UIColor *)titleColor
                   iconTint:(nullable UIColor *)iconTint
                 disclosure:(BOOL)disclosure;

/// 「添加例外」：主色圆 32 + 白色「＋」16。
- (void)configureAddCircleWithTitle:(NSString *)title;

/// 追加多行副文案（满员提示）。传 nil 隐藏。行高由调用方给出。
- (void)setDetailAttributedText:(nullable NSAttributedString *)text;

@end

NS_ASSUME_NONNULL_END
