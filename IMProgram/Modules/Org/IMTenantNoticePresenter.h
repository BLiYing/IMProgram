//  IMTenantNoticePresenter.h
//  审计告知（TENANT_DESIGN v2 §6.3，交互稿 I-13）：后台添加 / 代建的成员，directory/me 的
//  notice_pending=true 时在主界面弹一次「你已加入「集团」」，唯一按钮「我知道了」→ notice-ack。
//  ack 失败不重试，下次快照（重连 / 回前台 / 冷启动）仍是 pending 时再弹。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTenantNoticePresenter : NSObject

+ (instancetype)shared;

/// 挂到主界面（IMMainTabBarController viewDidAppear 调，幂等）；之后快照变化时自动判断弹不弹。
- (void)attachToHost:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
