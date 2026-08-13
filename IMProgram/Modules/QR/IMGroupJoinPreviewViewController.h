//  IMGroupJoinPreviewViewController.h
//  扫码/点链接后的「加群预览页」（G3，sketch §05）：群头像 + 名 + 人数 + 邀请人 + 附言 + 主按钮。
//  替换 IMQRResultRouter 里兜底的 UIAlertController——弹窗装不下头像，也不是"页"。

#import <UIKit/UIKit.h>
#import "IMQRModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupJoinPreviewViewController : UIViewController

/// push 进当前导航栈（复用容器注入的液态标题栏，与扫码进资料页一致）。
/// @param from     发起页（用其 navigationController push）。
/// @param host     服务器 host（拼群头像相对 URL）。
/// @param action   由 IMQRGroupActionForCard 算出（加入/申请/已在群进入/不可加入）。
/// @param onSubmit 主按钮回调；Apply 回带附言，其余回带 @""；Disabled 时按钮不可点、不回调。
+ (void)pushFrom:(UIViewController *)from
            host:(NSString *)host
            card:(IMQRGroupCard *)card
          action:(IMQRGroupAction)action
        onSubmit:(void (^)(NSString *hello))onSubmit;

@end

NS_ASSUME_NONNULL_END
