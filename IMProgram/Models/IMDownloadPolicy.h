//  IMDownloadPolicy.h
//  自动下载**决策**（M4-7）：给定策略、当前网络、类别、大小、单/群，判定这条媒体是否应静默预取。
//  纯函数，便于单测决策矩阵。消息到达时由聊天层调用；返回 NO 则卡片留"未下载"门控（用户点 ↓ 才下）。

#import <Foundation/Foundation.h>
#import "IMDownloadSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// 当前网络类型（由 NWPathMonitor 实时判定；None=离线，此时一律不自动下）。
typedef NS_ENUM(NSInteger, IMNetworkType) {
    IMNetworkTypeNone = 0,
    IMNetworkTypeWifi,
    IMNetworkTypeCellular,
};

/// 是否应自动下载。
/// @param settings    账号级策略（nil 回退默认）
/// @param contentType `image` / `video` / `file`（其它类型如语音由调用方另判：语音恒自动）
/// @param sizeBytes   媒体本体字节数（0=未知）
/// @param isGroup     该消息是否群聊
/// @param network     当前网络
///
/// 规则：离线→NO；该网络总开关关→NO；该类别的单/群开关关→NO；
///      图片→YES（无大小闸）；视频/文件→仅当 `sizeBytes>0 且 <= maxBytes`（maxBytes=0 即"手动"，恒 NO；
///      大小未知也保守判 NO，让用户点 ↓，避免弱网误拉大文件）。
FOUNDATION_EXPORT BOOL IMShouldAutoDownload(IMDownloadSettings *_Nullable settings,
                                            NSString *contentType,
                                            int64_t sizeBytes,
                                            BOOL isGroup,
                                            IMNetworkType network);

NS_ASSUME_NONNULL_END
