//  IMSessionTeardown.m

#import "IMSessionTeardown.h"
#import "IMRtcCall.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMSessionStore.h"
#import "IMDatabase.h"
#import "IMDatabase+AccountWipe.h"
#import "IMImageLoader.h"
#import "IMViewedMediaStore.h"
#import "IMLoginViewController.h"
#import "IMPendingMediaStore.h"
#import "IMChatFolderStore.h"
#import "IMRemarkStore.h"
#import "IMLog.h"

static BOOL sAccountDeletionInProgress = NO;

@implementation IMSessionTeardown

+ (BOOL)accountDeletionInProgress { return sAccountDeletionInProgress; }
+ (void)setAccountDeletionInProgress:(BOOL)v { sAccountDeletionInProgress = v; }

+ (void)tearDownLocalSession {
    [IMRtcCall.shared stop]; // 通话服务跟着账号走，否则换号后同一设备会有两条 im-rtc 连接
    [IMSocketManager.sharedManager disconnect];
    [IMHTTPService.sharedService invalidateToken];
    IMHTTPService.sharedService.refreshToken = nil; // 内存里的续期凭据也要清，否则本进程内还能换到 token
    [IMSessionStore clear]; // 清持久化会话，下次启动回登录页
}

+ (NSArray<NSURL *> *)ownedMediaCacheDirectories {
    NSURL *caches = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
                                                appropriateForURL:nil create:NO error:NULL];
    if (!caches) { return @[]; }
    return @[[caches URLByAppendingPathComponent:@"IMDownloads" isDirectory:YES],
             [caches URLByAppendingPathComponent:@"im_original_videos" isDirectory:YES]];
}

+ (void)wipeLocalChatCacheThen:(void (^)(void))completion {
    NSArray<NSURL *> *dirs = [self ownedMediaCacheDirectories];
    // 先断 WS：清库期间服务端仍在推帧，落库会把刚清掉的 owner 行又写回来（此时 owner 还在，tearDown 在 completion 里）。
    [IMSocketManager.sharedManager disconnect];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // 待发暂存目录各账号共用：只删本账号消息引用的文件（须在清库前取），别的账号的待发媒体不动。
        NSArray<NSString *> *pendingRefs = [IMDatabase.sharedDatabase pendingMediaLocalRefsForCurrentOwner];
        if (![IMDatabase.sharedDatabase wipeAllDataForCurrentOwner]) {
            IMLogWarnWithTag(IMLogTagDatabase, @"account_wipe_db_failed（继续清文件缓存并回登录页）");
        }
        for (NSURL *dir in dirs) { [NSFileManager.defaultManager removeItemAtURL:dir error:NULL]; }
        for (NSString *ref in pendingRefs) { [IMPendingMediaStore.shared removeLocalRef:ref]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[IMImageLoader shared] clearCache];
            [IMViewedMediaStore.shared clearCurrentUser];
            [IMChatFolderStore.shared wipeLocalState];
            [IMRemarkStore.sharedStore wipeDeletedMarksForCurrentOwner];
            completion();
        });
    });
}

+ (void)showLoginInWindow:(UIWindow *)window notice:(NSString *)notice {
    IMLoginViewController *login = [IMLoginViewController new];
    login.initialNotice = notice;
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

@end
