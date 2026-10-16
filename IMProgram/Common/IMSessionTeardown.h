//  IMSessionTeardown.h
//  「退出登录」与「注销账号」共用的本机会话收尾（原写在 IMSettingsViewController.logout 里）。
//  抽出来的原因：注销成功后必须走**同一条**清会话路径（DELETE_ACCOUNT_DESIGN.md §3.4），再多清一层聊天缓存。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionTeardown : NSObject

/// 停通话、断 WS、作废 token、擦续期凭据、清持久化会话。不碰 UI、不碰聊天缓存。
+ (void)tearDownLocalSession;

/// 注销请求在途 / 刚成功的窗口：服务端会立刻踢掉本机 WS，SceneDelegate 的「被踢下线」通路此时必须让路，
/// 否则会抢先回登录页（无「账号将在 7 天后删除」提示、也没清聊天缓存）。主线程读写。
@property (class, nonatomic, assign) BOOL accountDeletionInProgress;

/// 清本机属于当前账号的聊天缓存：本地库全部 owner 行 + 下载文件 / 视频原件 / 图片缓存 + 「看过」登记。
/// **必须在 tearDownLocalSession 之前调**（还要靠当前 owner / 当前 uid 定位数据）。
+ (void)wipeLocalChatCache;

/// 把 window 的根换成登录页；notice 非空时登录页顶部显示非红色提示条。
+ (void)showLoginInWindow:(nullable UIWindow *)window notice:(nullable NSString *)notice;

@end

NS_ASSUME_NONNULL_END
