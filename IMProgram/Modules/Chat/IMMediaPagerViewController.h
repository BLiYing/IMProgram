//  IMMediaPagerViewController.h
//  会话媒体时间线横向翻页容器（任务3）：把 N 个 IMMediaViewerViewController 串成左右翻页，
//  混排图片/视频（Telegram 式）。每页由 pageProvider 现建，翻页时旧页收到 viewDidDisappear
//  → 视频自动暂停（决策 A：封面待点，不自动播）。仅覆盖内存中已加载的媒体，翻到头即停。

#import <UIKit/UIKit.h>
#import "IMMediaViewerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPagerViewController : UIViewController

/// @param count        媒体总数（时间线长度，下标 0 为最旧、count-1 为最新）。
/// @param startIndex   进入时定位到的下标（点中的那张）。
/// @param pageProvider 按下标现建查看器页；须返回**已按该下标对应媒体配置好**的 viewer
///                     （url/isVideo/moreActions 等），容器会写回其 imMediaIndex。越界不会被调用。
+ (instancetype)pagerWithCount:(NSUInteger)count
                    startIndex:(NSUInteger)startIndex
                  pageProvider:(IMMediaViewerViewController *_Nullable (^)(NSUInteger index))pageProvider;

@end

NS_ASSUME_NONNULL_END
