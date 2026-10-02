//  IMMediaPagerViewController.h
//  会话媒体时间线横向翻页容器（任务3）：把 N 个 IMMediaViewerViewController 串成左右翻页，
//  混排图片/视频（Telegram 式）。每页由 pageProvider 现建，翻页时旧页收到 viewDidDisappear
//  → 视频自动暂停（决策 A：封面待点，不自动播）。仅覆盖内存中已加载的媒体，翻到头即停。

#import <UIKit/UIKit.h>
#import "IMMediaViewerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPagerViewController : UIViewController

/// 顶部标题栏主标题：所在会话（群/单聊）名称。空则只显副标题（数目）。翻页前设置。
@property (nonatomic, copy, nullable) NSString *conversationTitle;

/// 服务端续拉（有缺口且在线时由宿主接，OFFLINE_BACKLOG_DESIGN §4.9 第 5 项）。靠近「更旧」那一头时容器自动预取，
/// 宿主在 `done` 里回报新增条数；宿主的 `pageProvider` 必须按**调用时**的时间线取数（时间线会变长）。
/// 不设则维持「翻到头即停」。
@property (nonatomic, copy, nullable) void (^olderLoader)(void (^done)(NSInteger added));
/// 还有没有更旧的（nil = 恒有；不设 `olderLoader` 时无意义）。
@property (nonatomic, copy, nullable) BOOL (^hasOlder)(void);
/// 更旧的一头在**末尾**（媒体库新→旧排序，续拉追加在后面，下标不挪）；默认 NO = 在开头（升序，续拉前插，当前下标要后移）。
@property (nonatomic, assign) BOOL olderAtEnd;

/// @param count        媒体总数（时间线长度，下标 0 为最旧、count-1 为最新）。
/// @param startIndex   进入时定位到的下标（点中的那张）。
/// @param pageProvider 按下标现建查看器页；须返回**已按该下标对应媒体配置好**的 viewer
///                     （url/isVideo/thumb/moreActions 等），容器会写回其 imMediaIndex。越界不会被调用。
+ (instancetype)pagerWithCount:(NSUInteger)count
                    startIndex:(NSUInteger)startIndex
                  pageProvider:(IMMediaViewerViewController *_Nullable (^)(NSUInteger index))pageProvider;

@end

NS_ASSUME_NONNULL_END
