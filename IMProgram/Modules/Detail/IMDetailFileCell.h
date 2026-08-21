//  IMDetailFileCell.h
//  详情页「文件」页签的文件行 Cell（三态：未下载 / 下载中 / 已下载，草图 §04）。
//  左图标位即状态位；无右侧配件，点行=下载/暂停/继续/打开。从 IMChatDetailViewController.m 抽出，未改行为。

#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMDetailFileCell : UITableViewCell
/// 收藏页复用时设来源名（非空 → 副行下再加一行「来自X · 时间」；详情页留 nil=只显时间）。**须在 configure 前设。**
@property (nonatomic, copy, nullable) NSString *sourceName;
- (void)configureWithMessage:(IMMessageModel *)m download:(nullable IMDownloadProgress *)dp;
/// 进度**就地更新**（不 reload）：只改图标位环/字形 + 副行文案；文件名不变。
- (void)updateDownload:(nullable IMDownloadProgress *)dp;
@end

NS_ASSUME_NONNULL_END
