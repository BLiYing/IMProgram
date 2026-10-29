//  IMClearAllViewController.h
//  清除所有对话二级页（隐私与安全 → 数据）。3 态：配置 → 系统二次确认 → 成功返回隐私页 toast（失败内联红字、按钮恢复）。
//  设计 IMServer/docs/design/CLEAR_ALL_CONVERSATIONS_DESIGN.md §1 §4；草图 sketches/CLEAR_ALL_CONVERSATIONS_UX_SKETCH.html。
//  版式取自共用的 IMDangerPageViewController（与注销账号同款）；无密码框。

#import "IMDangerPageViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMClearAllViewController : IMDangerPageViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
