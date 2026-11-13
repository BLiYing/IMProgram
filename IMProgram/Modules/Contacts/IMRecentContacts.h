//  IMRecentContacts.h
//  通讯录首页「最近联系」的取数（纯函数，三端同一口径；设计 ../IMServer/docs/design/ORG_DIRECTORY_DESIGN.md §7.1）。
//  输入是内存里已有的会话列表，不查消息库、不拉接口。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

/// 「最近联系」最多显示几个。
FOUNDATION_EXPORT const NSUInteger kIMRecentContactsLimit;

/// 最近和我有过单聊消息往来的人，按最后一条消息时间倒序，最多 kIMRecentContactsLimit 个。
/// - 只要单聊；排除：和自己的会话、系统通知会话、对端 uid 为空、对方已注销、没有任何消息（时间 <= 0）。
/// - 时间相同按会话 ID 升序，保证三端顺序一致。
/// - **不看置顶 / 未读 / 免打扰**；输入顺序不影响结果。
/// isDeletedUser：补充的「已注销」判定（会话行的 peerDeleted 不落本地库，冷启动要靠 IMRemarkStore 的登记）；
/// 传 nil 则只看 peerDeleted。
FOUNDATION_EXPORT NSArray<IMConversation *> *IMRecentContacts(NSArray<IMConversation *> *_Nullable conversations,
                                                              NSString *_Nullable selfUID,
                                                              BOOL (^_Nullable isDeletedUser)(NSString *peerUID));

NS_ASSUME_NONNULL_END
