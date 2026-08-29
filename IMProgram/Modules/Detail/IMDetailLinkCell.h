//  IMDetailLinkCell.h
//  详情页「链接」tab 单行。视觉对齐 IMDetailFileCell 三行 16/12/12 pt（草图 docs/design/sketches/URL_LINK_UX_SKETCH.html §C）：
//  favicon（首字母圈，与 og 抓取的实际 favicon 未接入）+ t1 og:title(host 兜底) + t2 host+path(mono) + t3 时间。
//  点整行=打开链接（不跳原消息，草图定案）；无来源、无原文预览（收藏页那两行归 §D 单独实现）。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMDetailLinkCell : UITableViewCell
/// message.content 应为完整 URL；命中 IMLinkCardCell.previewCache 直接展开 og:title。
/// 未命中触发异步抓取，抓到后就地把 t1 替换成 og:title（不改行高，无需回调宿主刷表）。
- (void)configureWithMessage:(IMMessageModel *)message;
@end

NS_ASSUME_NONNULL_END
