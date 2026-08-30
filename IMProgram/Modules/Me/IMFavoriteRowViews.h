//  IMFavoriteRowViews.h
//  收藏页的三个小展示件——从 `IMFavoritesViewController.m` 抽出（该文件撞了 1500 行体量红线，
//  CODING_STYLE §7）。三者只吃入参、不碰页面状态，天然可独立成文件：
//   · `IMFavoriteReaderViewController` —— 点文本收藏 → 全文只读页（FAVORITES_DESIGN §5.6）
//   · `IMFavoriteRowCell`              —— 文本 / 聊天记录 / 语音兜底的统一 52pt 图标行（§4.1 / §12）
//   · `IMFavoriteSourceCell`           —— 聊天模式的来源会话行（头像 + 名 + 最近预览 + 计数）
//  链接行走独立的 `IMFavoriteLinkCell`、语音行走 `IMFavoriteVoiceCell`、
//  文件/名片行复用详情页的 `IMDetailFileCell` / `IMDetailContactCell`（"收藏页复用资料详情页"）。

#import <UIKit/UIKit.h>
#import "IMFavoritesCategories.h"   // IMFavoriteCategory

NS_ASSUME_NONNULL_BEGIN

/// 收藏文本全文只读页。
@interface IMFavoriteReaderViewController : UIViewController
- (instancetype)initWithText:(NSString *)text;
@end

/// 统一图标行。`source` 非空时副行显「来自X」（accent），时间另起一行（tertiary）——
/// 两行分开是因为备注名/群昵称一长，单行「来自X · 年月日时分」会把时间截没。
@interface IMFavoriteRowCell : UITableViewCell
- (void)configureWithFavorite:(NSDictionary *)fav kind:(IMFavoriteCategory)kind source:(nullable NSString *)source;
@end

/// 聊天模式的来源会话行。
@interface IMFavoriteSourceCell : UITableViewCell
- (void)configureWithName:(NSString *)name avatarURL:(nullable NSString *)avatarURL seed:(NSString *)seed
                  preview:(NSString *)preview count:(NSInteger)count;
@end

NS_ASSUME_NONNULL_END
