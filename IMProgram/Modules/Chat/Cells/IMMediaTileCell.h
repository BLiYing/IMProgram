//  IMMediaTileCell.h
//  会话媒体宫格通用格子（3 列方形，带下载门控）：资料页「媒体」tab 与全屏「图片与视频」库共用同一套，
//  外观/门控/长按一致（M4-7）。就绪=清晰缩略图/▶；未下载/下载中/暂停/失败=磨砂 + ↓/环形进度/↻ + 尺寸角标。

#import <UIKit/UIKit.h>
#import "IMConversationMediaViewController.h" // IMMediaItem

@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaTileCell : UICollectionViewCell
/// @param download nil=就绪（正常显缩略图/▶）；非 nil=未下载/下载中/暂停/失败 → 显 ↓/环形进度 + 尺寸角标，
///                 且**不拉原图**（只显 thumb 模糊占位）。草图 §04「未下载格显 ↓ + 尺寸角标」。
- (void)configureWithItem:(IMMediaItem *)item download:(nullable IMDownloadProgress *)download thumb:(nullable NSString *)thumb;
/// 进度**就地更新**（不 reload）：只改该格的环/中心图标/尺寸角标，不动缩略图。
- (void)updateDownload:(nullable IMDownloadProgress *)dp;

/// pick 模式勾选框（收藏 pick）：右上角圆形，点击独立触发 onCheckboxTap，不冒泡给格子选中。
/// pickMode=NO 时清空覆盖层；默认 NO，不影响其它调用方（详情/媒体库）。
- (void)setPickMode:(BOOL)pickMode selected:(BOOL)selected onCheckboxTap:(nullable void (^)(void))onTap;
@end

NS_ASSUME_NONNULL_END
