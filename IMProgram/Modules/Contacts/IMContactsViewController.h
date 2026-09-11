//  IMContactsViewController.h
//  通讯录 Tab：新的朋友（待处理申请，同意/拒绝）+ 好友列表（点击发起会话）。右上角 + 进找人页。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 切入通讯录时是否要拉权威好友列表（节流判据，纯函数便于单测）。
/// 从未拉成功过（lastRefreshAt<=0）必拉——本地好友缓存只由本页写入，不拉就永远是空的；
/// 已有请求在途不重复发；距上次成功不足 interval 秒不拉；now 早于 lastRefreshAt（时钟异常）按过期处理，别卡死。
/// 好友事件 / 重连 / 本页增删拉黑触发的刷新不走这道节流。
extern BOOL IMContactsShouldRefreshOnAppear(BOOL inFlight, CFTimeInterval lastRefreshAt,
                                            CFTimeInterval now, CFTimeInterval interval);

@interface IMContactsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
