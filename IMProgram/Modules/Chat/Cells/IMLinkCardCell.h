#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkCardCell : UITableViewCell
/// 长按菜单高亮/收起动画的目标视图（=卡片本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

NS_ASSUME_NONNULL_END
