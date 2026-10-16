//
//  NSObject+IMCoalescedPerform.h
//  合并式延迟调用（尾部去抖）：窗口内重复请求只执行最后一次。
//
//  为什么有：群帧会连发（一次邀请 100 人曾推 100 帧），每帧都整份 GET 群资料 + 整表刷新会把页面拖到分钟级。
//  聊天页 / 群详情 / 群管理 / 管理员列表四处的 onGroupEvent: 共用这一对方法，终态事件（群解散 / 被移出）
//  要先 im_cancelCoalescedPerform: 撤掉已排队的重拉，免得页面退场后重拉吃 300201 再弹一次——
//  这条规则写在一处，不再四处各抄一份。
//
//  注意：基于 performSelector:afterDelay:（默认 RunLoop 模式），列表正在滚动时会推迟到滚动结束，这是有意的
//  （滚动中途整表刷新体验更差）；窗口内 self 会被强持有，窗口很短，可忽略。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 群事件触发的重拉的合并窗口（秒）。
FOUNDATION_EXPORT const NSTimeInterval IMGroupEventCoalesceDelay;

@interface NSObject (IMCoalescedPerform)

/// 在 delay 秒后调用 selector（无参）；窗口内再次调用会取消上一次排队，只保留最后一次。
- (void)im_coalescedPerform:(SEL)selector afterDelay:(NSTimeInterval)delay;

/// 撤销尚未触发的合并调用；没有排队则无操作。
- (void)im_cancelCoalescedPerform:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
