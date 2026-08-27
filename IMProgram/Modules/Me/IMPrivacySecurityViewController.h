//  IMPrivacySecurityViewController.h
//  隐私与安全容器页——对应设置页「隐私与安全」入口（原直接跳黑名单，现改为跳本页）。
//  设计见 IMServer/docs/PRIVACY_SECURITY_DESIGN.md；草图 PRIVACY_SECURITY_UX_SKETCH.html。
//
//  组 A（安全，P0）：已屏蔽的用户 + 修改密码
//  组 B/C/D/E（P2 占位）：两步验证 / 通行密钥 / 邮箱登录 / 自动删除消息 / 谁能看到 / 清除对话 / 导出数据

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPrivacySecurityViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
@end

NS_ASSUME_NONNULL_END
