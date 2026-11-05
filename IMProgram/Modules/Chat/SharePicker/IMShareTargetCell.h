//  IMShareTargetCell.h
//  分享选择页的行：行首圆形勾选框（仅多选态）+ 头像圈 + 名字；以及「我的好友 / 我的群聊」入口行。
//  原是 IMForwardPickerViewController.m 里的私有 IMForwardPickerCell，好友 / 群聊子页也要用，故拆出来。
//  另带一个「标题 + 副标题（已选 N/9）」的导航栏 titleView 构造函数，三页共用。

#import <UIKit/UIKit.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMShareTargetCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)c multiSelect:(BOOL)multiSelect selected:(BOOL)selected;
@end

/// 入口行：彩色圆角方块图标（SF Symbol）+ 标题 + 「›」。
@interface IMShareEntryCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint;
@end

/// 导航栏标题；subtitle 为空时只有一行标题。
FOUNDATION_EXPORT UIView *IMShareTitleView(NSString *title, NSString *_Nullable subtitle);

NS_ASSUME_NONNULL_END
