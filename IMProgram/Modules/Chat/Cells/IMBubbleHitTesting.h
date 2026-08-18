//  IMBubbleHitTesting.h
//  让聊天页的表级点击手势（handleReplyJumpTap:）把「打开文件 / 引用跳转 / 长文展开」限制在**真正的气泡/
//  卡片/缩略图**上，而不是整行横向空白。根因：手势靠 indexPathForRowAtPoint 命中整行，气泡通常窄于行宽
//  （≤0.75 宽 + 单侧对齐），旁边留白也被算作命中。各消息 cell 实现本方法，返回自身气泡视图对给定点的命中判断。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol IMBubbleHitTesting <NSObject>
/// pointInCell 为 cell 自身坐标系下的点；YES=落在可交互气泡区域内（才放行打开/跳转/展开）。
- (BOOL)pointInsideBubble:(CGPoint)pointInCell;
@end

NS_ASSUME_NONNULL_END
