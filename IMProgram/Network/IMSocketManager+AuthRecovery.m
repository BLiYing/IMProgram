//
//  IMSocketManager+AuthRecovery.m
//  握手 401 → 先续期再判被踢。判据见头文件 IMSocketUnauthorizedActionFor。
//

#import "IMSocketManager+AuthRecovery.h"
#import "IMSocketManager+Private.h"
#import "IMHTTPService.h"
#import "IMLog.h"

IMSocketUnauthorizedAction IMSocketUnauthorizedActionFor(BOOL retriedAfterRefresh) {
    return retriedAfterRefresh ? IMSocketUnauthorizedActionRevoked : IMSocketUnauthorizedActionRefresh;
}

@implementation IMSocketManager (AuthRecovery)

- (BOOL)recoverFromAuthRejection {
    if (IMSocketUnauthorizedActionFor(_retriedAfterRefresh) == IMSocketUnauthorizedActionRevoked) {
        IMLogWarnWithTag(IMLogTagSocket, @"ws_handshake_401_revoked afterRefresh=1");
        _retriedAfterRefresh = NO;
        return NO;
    }
    IMLogSocket(@"ws_handshake_401_refreshing");
    _retriedAfterRefresh = YES;
    // 丢掉 10 分钟缓存里那枚被拒的 token：openSocket → fetchTokenForHost: → loginWithUserID: 随即 miss 缓存、
    // 凭续期凭据换新票。续期的三种结局都由既有通路接住：
    //  · 换到了 → 照常连上（didOpen 清 _retriedAfterRefresh）；
    //  · 被服务端拒绝 → IMHTTPService+Auth 擦凭据并发 IMSocketDidRevokeSessionNotification（回登录页）；
    //  · 连不上 → openSocket 退避重连，下一轮缓存仍是空的，接着续期。
    [IMHTTPService.sharedService invalidateToken];
    _reconnectAttempts = 0;
    [self openSocket];
    return YES;
}

@end
