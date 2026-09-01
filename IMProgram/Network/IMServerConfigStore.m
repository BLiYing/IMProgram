//
//  IMServerConfigStore.m
//

#import "IMServerConfigStore.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMLog.h"

@implementation IMServerConfigStore {
    BOOL _started;
}

+ (instancetype)shared {
    static IMServerConfigStore *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMServerConfigStore new]; });
    return inst;
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketStateChanged:)
                                               name:IMSocketDidChangeStateNotification object:nil];
    [self refresh]; // 冷启动已有会话时 token 可能已就绪
}

- (void)onSocketStateChanged:(NSNotification *)note {
    // 部署配置一次会话内不会变，拉到就不必再拉；没拉到（首次/上次失败）才在连上时补一发。
    if (_loaded) { return; }
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 还没登录，等下次
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService serverConfigWithToken:token
                                            completion:^(NSInteger maxGroupMembers,
                                                         BOOL supergroupEnabled,
                                                         NSInteger maxSupergroupMembers,
                                                         NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            // **失败不写默认值**：loaded 保持 NO，依赖它的 UI 就当"未知"不显示。
            // 写个猜测值进去会让"群已满"这类提示按错误的上限误报。
            IMLogWarnWithTag(IMLogTagHTTP, @"server_config_fetch_failed error=%@", error.localizedDescription ?: @"");
            return;
        }
        self->_maxGroupMembers = maxGroupMembers;
        self->_supergroupEnabled = supergroupEnabled;
        self->_maxSupergroupMembers = maxSupergroupMembers;
        self->_loaded = YES;
    }];
}

@end
