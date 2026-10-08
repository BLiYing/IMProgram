//
//  IMSocketManager+AuthRecovery.m
//  握手 401 → 先续期再判被踢。判据见头文件 IMSocketUnauthorizedActionFor。
//

#import "IMSocketManager+AuthRecovery.h"
#import "IMSocketManager+Private.h"
#import "IMHTTPService.h"
#import "IMLog.h"

IMSocketUnauthorizedAction IMSocketUnauthorizedActionFor(BOOL hasRefreshCredential,
                                                         NSUInteger failedGeneration,
                                                         NSUInteger refreshRetryGeneration) {
    if (!hasRefreshCredential) { return IMSocketUnauthorizedActionRevoked; }
    if (refreshRetryGeneration != 0 && failedGeneration == refreshRetryGeneration) { return IMSocketUnauthorizedActionRevoked; }
    return IMSocketUnauthorizedActionRefresh;
}

@implementation IMSocketManager (AuthRecovery)

- (BOOL)recoverFromAuthRejection {
    IMHTTPService *http = IMHTTPService.sharedService;
    BOOL hasCredential = http.refreshToken.length > 0;
    if (IMSocketUnauthorizedActionFor(hasCredential, _connectionGeneration, _refreshRetryGeneration)
        == IMSocketUnauthorizedActionRevoked) {
        IMLogWarnWithTag(IMLogTagSocket, @"ws_handshake_401_revoked has_credential=%d after_refresh=%d",
                         hasCredential, _connectionGeneration == _refreshRetryGeneration);
        return NO;
    }
    IMLogSocket(@"ws_handshake_401_refreshing");
    // 只让缓存过期（不清 currentToken / 昵称）：openSocket → fetchTokenForHost: → loginWithUserID: 随即 miss 缓存、
    // 凭续期凭据换新票。续期的三种结局都由既有通路接住：
    //  · 换到了 → 照常连上；
    //  · 被服务端以鉴权码拒绝（含封号 200003）→ IMHTTPService+Auth 擦凭据并发 IMSocketDidRevokeSessionNotification；
    //  · 连不上 / 服务端临时出错 → openSocket 退避重连，下一轮缓存仍是过期的，接着续期。
    [http expireCachedToken];
    _reconnectAttempts = 0;
    [self openSocket];
    _refreshRetryGeneration = _connectionGeneration; // openSocket 同步 ++ 了代次：这一条就是「续期后开的」
    return YES;
}

@end
