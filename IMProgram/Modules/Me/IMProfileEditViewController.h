//  IMProfileEditViewController.h
//  编辑我的资料：昵称/头像 URL/手机号/标签。GET /users/me 回填，PUT /users/me 保存。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMProfileEditViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

/// 进页即编辑态（设置页右上角「编辑」，2026-10-07 三端同口径）。编辑就是这一趟的目的：
/// 取消 / 保存成功都直接退回上一页，不落回只读态（否则要多点一次返回）。默认 NO = 只读 ↔ 编辑双态。
@property (nonatomic, assign) BOOL startsEditing;

@end

NS_ASSUME_NONNULL_END
