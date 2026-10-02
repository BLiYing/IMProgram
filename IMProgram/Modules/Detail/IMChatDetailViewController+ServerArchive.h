//  IMChatDetailViewController+ServerArchive.h
//  资料页「媒体 / 文件 / 语音」页签的服务端分页接线（持有者见 IMDetailServerArchive）。

#import "IMChatDetailViewController+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMChatDetailViewController (ServerArchive)

/// 进页后调一次：本地有缺口且在线就起服务端归档并要第一页；本地齐全什么都不做。
- (void)im_startServerArchiveIfNeeded;
/// 页签数据源：本地归档 ∪ 服务端已拉到的（没起服务端归档时原样返回）。
- (NSArray<IMMessageModel *> *)im_archiveMergedWithLocal:(NSArray<IMMessageModel *> *)local;
/// 滚到接近底部时调：当前页签由服务端分页供给且还有更多就续拉。
- (void)im_loadMoreArchiveIfNearBottom:(UIScrollView *)scrollView;

@end

NS_ASSUME_NONNULL_END
