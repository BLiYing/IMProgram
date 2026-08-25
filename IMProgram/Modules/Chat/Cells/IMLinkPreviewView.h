//  IMLinkPreviewView.h
//  文本气泡内嵌的 URL 富预览子视图（缩略图 + 标题 + 描述 + 站名）。
//  与 IMLinkCardCell 的 OG 卡片视觉一致，但作为通用子视图挂在**任意气泡**（IMBubbleCell 文本正文里
//  首个 URL 都可挂），复用同一处 IMLinkCardCell.previewCache 与后端 /api/v1/link-preview 抓取通路。
//
//  行为：configureWithURL: 触发异步抓取；命中缓存同步渲染；抓不到 og（title/image 都空）→ 保持隐藏
//  ->onContentSizeResolved 让宿主刷新行高。宿主负责在气泡内布局本视图（顶接文本底、底接气泡底）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkPreviewView : UIView

/// 触发 URL 抓取 + 渲染。传空/nil 或非 http(s) → 静默隐藏（hidden=YES，intrinsic 尺寸归零）。
/// 重复调用同一 URL 命中缓存直接返回，不重发请求；同一 URL 多处挂载共享同一 in-flight（IMLinkCardCell 已实现）。
- (void)configureWithURL:(nullable NSString *)url;

/// 卡片可见（有 og:title 或 og:image）且用户点了它 → 打开链接。宿主一般传 openLink: 的封装。
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);

/// 卡片从"未拉到"变"已渲染"（第一次可见）时回调一次，用于宿主刷行高（IMBubbleCell 内嵌时行高会变）。
/// 与 IMLinkCardCell.onContentSizeResolved 同款守卫：宿主自己在滚动中要延迟到停止再 reload。
@property (nonatomic, copy, nullable) void (^onContentSizeResolved)(void);

/// 当前是否有可展示的预览（title/image 至少一个非空）。宿主判断行高是否包含本视图。
@property (nonatomic, readonly) BOOL hasContent;

@end

NS_ASSUME_NONNULL_END
