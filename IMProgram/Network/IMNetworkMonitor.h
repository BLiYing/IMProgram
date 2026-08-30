//  IMNetworkMonitor.h
//  当前网络类型的实时来源（M4-7），包装 Network.framework 的 nw_path_monitor。
//  自动下载决策（IMShouldAutoDownload）据此判定用移动数据档还是 Wi-Fi 档。

#import <Foundation/Foundation.h>
#import "IMDownloadPolicy.h" // IMNetworkType

NS_ASSUME_NONNULL_BEGIN

/// 网络从**不可达变为可达**时广播（主线程）。只报这一个跃迁——「断了」不需要谁立刻做什么，
/// 「回来了」才是要立即重连的信号（IMSocketManager 观察它跳过指数退避，见 docs/TASKS.md §3.5）。
/// 首帧不报：启动时乐观视作可达，避免冷启动多打一次重连。
extern NSString * const IMNetworkDidBecomeReachableNotification;

@interface IMNetworkMonitor : NSObject

+ (instancetype)shared;

/// 当前网络类型。首帧到达前乐观回 Wi-Fi（不误伤默认自动下载）；离线为 None。
@property (nonatomic, assign, readonly) IMNetworkType currentType;

/// 开始监听（App 启动时调一次，幂等）。
- (void)start;

@end

NS_ASSUME_NONNULL_END
