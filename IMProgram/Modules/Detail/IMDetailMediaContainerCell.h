//  IMDetailMediaContainerCell.h
//  详情页「媒体」页签内联的 3 列宫格 Cell（内嵌 CollectionView，格子复用 IMMediaTileCell）。
//  逐格门控/进度/长按菜单都经 block 由 VC 注入。从 IMChatDetailViewController.m 抽出，未改行为。

#import <UIKit/UIKit.h>

@class IMMediaItem;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMDetailMediaContainerCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onPick)(IMMediaItem *item);
/// 逐格门控（M4-7）：返回 nil=该格就绪；非 nil=未下载/下载中/暂停/失败，点击走 onDownloadItemIndex。
@property (nonatomic, copy, nullable) IMDownloadProgress *_Nullable (^stateForItemIndex)(NSInteger index);
/// 该格的极小模糊预览（thumb data URI），门控时用作占位。
@property (nonatomic, copy, nullable) NSString *_Nullable (^thumbForItemIndex)(NSInteger index);
/// 门控格点击（开始/暂停/继续/重试）。
@property (nonatomic, copy, nullable) void (^onDownloadItemIndex)(NSInteger index);
/// 内容宽确定/变化时回调（供外部按真实宽度重算行高，消除卡片底部白边）。
@property (nonatomic, copy, nullable) void (^onContentWidthChanged)(CGFloat width);
/// 逐格长按菜单（任务2：转发/定位到聊天/[取消下载]/删除两档，与文件行一致）——由 VC 提供，返回 nil=不显示。
@property (nonatomic, copy, nullable) UIContextMenuConfiguration *_Nullable (^contextMenuForItemIndex)(NSInteger index);
- (void)setItems:(NSArray<IMMediaItem *> *)items;
/// 重配一格（用于「下载完成/解除门控」——需要重新拉原图）。
- (void)refreshItemAtIndex:(NSInteger)index;
/// 进度**就地更新**一格（高频回调用）：只改该格的环/图标/角标，不 reloadItems。
- (void)updateItemAtIndex:(NSInteger)index download:(nullable IMDownloadProgress *)dp;
+ (CGFloat)heightForCount:(NSInteger)count width:(CGFloat)width;
@end

NS_ASSUME_NONNULL_END
