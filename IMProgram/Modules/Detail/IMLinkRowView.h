//  IMLinkRowView.h
//  通用 URL 卡视图（36×36 favicon + t1 og:title(host 兜底) + t2 host+path(mono) + t3 时间）。
//  三处消费：详情页链接 tab（IMDetailLinkCell）· 收藏页链接分类（IMFavoriteLinkCell）·
//  聊天页收藏面板的链接分类（Batch 2 落地）。
//
//  视觉规格：草图 docs/URL_LINK_UX_SKETCH.html §C UI 规格表（对齐 IMDetailFileCell 三行 16/12/12 pt）。
//  抓取通路复用 IMLinkCardCell.previewCache + IMHTTPService.linkPreviewWithToken:url:，
//  同一 URL 全站只抓一次（跨 view 共享缓存 key）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkRowView : UIView
/// url：完整 URL；timeText：t3 显示的时间文案（如"10:28" / "昨天 15:02" / "3月14日"），空则不占位。
- (void)configureWithURL:(NSString *)url timeText:(nullable NSString *)timeText;
@end

NS_ASSUME_NONNULL_END
