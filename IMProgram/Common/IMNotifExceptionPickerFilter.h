//  IMNotifExceptionPickerFilter.h
//  「添加例外」会话选择页的过滤判据（纯函数，可测）：NOTIFICATIONS_P1_DESIGN §2——
//  只列该类型（私聊/群聊）、还没免打扰、非系统通知会话（IMIsSystemUserID）的会话。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// isGroup/muted：该会话的当前状态；peer：单聊对端 uid（群聊传 nil，不参与系统通知判定）；
/// wantGroup：本页要的类型（私聊通知子页传 NO，群聊通知子页传 YES）。
FOUNDATION_EXPORT BOOL IMNotifExceptionPickerMatches(BOOL isGroup, BOOL muted, NSString *_Nullable peer, BOOL wantGroup);

NS_ASSUME_NONNULL_END
