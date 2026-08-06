//  IMNetworkMonitor.h
//  当前网络类型的实时来源（M4-7），包装 Network.framework 的 nw_path_monitor。
//  自动下载决策（IMShouldAutoDownload）据此判定用移动数据档还是 Wi-Fi 档。

#import <Foundation/Foundation.h>
#import "IMDownloadPolicy.h" // IMNetworkType

NS_ASSUME_NONNULL_BEGIN

@interface IMNetworkMonitor : NSObject

+ (instancetype)shared;

/// 当前网络类型。首帧到达前乐观回 Wi-Fi（不误伤默认自动下载）；离线为 None。
@property (nonatomic, assign, readonly) IMNetworkType currentType;

/// 开始监听（App 启动时调一次，幂等）。
- (void)start;

@end

NS_ASSUME_NONNULL_END
