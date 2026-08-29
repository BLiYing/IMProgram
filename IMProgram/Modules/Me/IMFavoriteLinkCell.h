//  IMFavoriteLinkCell.h
//  收藏页 Links 分类专用行。视觉与详情页 IMDetailLinkCell 同基（都内嵌 IMLinkRowView），
//  再加两条收藏页特有信息：**原文引用**（混排文本"看看 https://xxx"的原句，仅混排时显）+
//  **来源行**（"来自 X · 时间"，与 IMFavoriteRowCell 的 meta 语义一致，永远显）。
//  草图 docs/design/sketches/URL_LINK_UX_SKETCH.html §D。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFavoriteLinkCell : UITableViewCell
/// url：抽取出的首个 URL（不是 favorite.content 全文）；quoteText：混排文本时=原文，纯 URL 时=nil；
/// sourceText：来源名（如"技术讨论群 · 张三"）；timeText：右下时间（如"2026-08-25 10:28"）。
- (void)configureWithURL:(NSString *)url
               quoteText:(nullable NSString *)quoteText
              sourceText:(nullable NSString *)sourceText
                timeText:(nullable NSString *)timeText;
@end

NS_ASSUME_NONNULL_END
