//  IMShareConfirmViewController.h
//  多选「发送(N)」后的确认面板（SHARE_PICKER_UX_SKETCH ④）：底部弹层，
//  「分别发送给（N）」+ 目标头像网格（每格 ✕ 可删，删到 0 自动收起）+ 内容预览 + 「发送」。
//  只负责展示与收集用户动作；选中集本身归选择页所有，删除经 onRemove 回给选择页去改。

#import <UIKit/UIKit.h>

@class IMShareSelection;

NS_ASSUME_NONNULL_BEGIN

@interface IMShareConfirmViewController : UIViewController

/// previewText 为空则不显示预览行。
- (instancetype)initWithSelection:(IMShareSelection *)selection
                      previewText:(nullable NSString *)previewText NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 网格里点 ✕。选择页改完选中集后调 reload；本页发现删空会自行收起。
@property (nonatomic, copy, nullable) void (^onRemove)(NSString *convID);
/// 点「发送」：本页先收起，completion 里回调。
@property (nonatomic, copy, nullable) void (^onConfirm)(void);

- (void)reload;

@end

NS_ASSUME_NONNULL_END
