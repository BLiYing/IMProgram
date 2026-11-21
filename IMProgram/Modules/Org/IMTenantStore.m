//  IMTenantStore.m

#import "IMTenantStore.h"
#import <UIKit/UIKit.h>
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Directory.h"
#import "IMLog.h"
#import "IMServerConfigStore.h"
#import "IMSocketManager.h"
#import "IMJSONValue.h"
#import "IMTimeUtil.h"

NSNotificationName const IMTenantStoreDidChangeNotification = @"IMTenantStoreDidChangeNotification";

/// 与 IMServerConfigStore 同一合并窗口：回前台与随后的 Connected 常在同一秒先后到。
static const int64_t kIMTenantMinRefreshIntervalMs = 5000;

@implementation IMTenantUnit

+ (NSArray<IMTenantUnit *> *)unitsFromArray:(id)array {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in IMJSONDicts(array)) {
        if (IMJSONString(d[@"unit_id"]).length == 0) { continue; }
        IMTenantUnit *u = [IMTenantUnit new];
        u.unitID = d[@"unit_id"];
        u.name = IMJSONString(d[@"name"]);
        u.isHQ = [IMJSONString(d[@"kind"]) isEqualToString:@"hq"];
        [out addObject:u];
    }
    return out;
}

@end

@implementation IMTenantStore {
    BOOL _started;
    BOOL _inFlight;
    BOOL _loaded;
    BOOL _hasTenant;
    int64_t _lastSuccessMs;
    NSString *_owner;        // 快照所属账号
    NSDictionary *_raw;      // 最近一次 me 响应（比较变化用）
}

+ (instancetype)shared {
    static IMTenantStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMTenantStore new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) { [self resetValues]; }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)resetValues {
    _loaded = NO; _hasTenant = NO; _isCustomer = NO; _isCS = NO; _noticePending = NO;
    _tenantName = @""; _unitName = @""; _deptName = @"";
    _bindings = @[];
    _raw = nil;
}

- (NSString *)currentOwner { return IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @""; }

/// 换号后旧快照作废：读值前先对一下账号。
- (void)dropIfAccountChanged {
    if (_owner.length > 0 && ![_owner isEqualToString:[self currentOwner]]) {
        _owner = nil;
        _lastSuccessMs = 0;
        [self resetValues];
    }
}

- (BOOL)hasTenant { [self dropIfAccountChanged]; return _hasTenant; }
- (BOOL)loaded { [self dropIfAccountChanged]; return _loaded; }

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(onSocketStateChanged:) name:IMSocketDidChangeStateNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(onFriendEvent:) name:IMSocketDidReceiveFriendEventNotification object:nil];
    [self refresh];
}

- (void)onSocketStateChanged:(NSNotification *)note {
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

/// 只有 org_exit 会改我的集团身份；其它好友事件不必重拉。
- (void)onFriendEvent:(NSNotification *)note {
    if ([note.userInfo[kIMFriendEventKey] isEqualToString:@"org_exit"]) { [self refreshNow]; }
}

- (void)refreshNow {
    _lastSuccessMs = 0;
    [self refresh];
}

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    if (![IMServerConfigStore shouldFetchWithInFlight:_inFlight lastSuccessMs:_lastSuccessMs
                                                nowMs:IMNowMillis() minIntervalMs:kIMTenantMinRefreshIntervalMs]) {
        return;
    }
    _inFlight = YES;
    NSString *owner = [self currentOwner]; // 发请求时的账号：回来时换号了就作废，别把上一个账号的身份记到新账号名下
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService directoryMeWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_inFlight = NO;
        if (![owner isEqualToString:[self currentOwner]]) {
            IMLogWithTag(IMLogTagHTTP, @"directory_me_dropped reason=account_changed");
            [self refreshNow]; // 在途期间新账号的刷新被 _inFlight 挡掉了，补拉一次
            return;
        }
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"directory_me_failed code=%ld", (long)error.code); // 保留上一份快照
            return;
        }
        self->_lastSuccessMs = IMNowMillis();
        [self applyMe:data ?: @{}];
    }];
}

- (BOOL)applyMe:(NSDictionary *)data {
    [self dropIfAccountChanged];
    NSString *owner = [self currentOwner];
    BOOL changed = !_loaded || ![_owner isEqualToString:owner] || ![_raw isEqualToDictionary:data];
    if (!changed) { return NO; }
    BOOL hadTenant = _hasTenant, wasLoaded = _loaded;
    [self resetValues];
    _owner = [owner copy];
    _raw = [data copy];
    _loaded = YES;
    NSDictionary *tenant = IMJSONDict(data[@"tenant"]);
    _hasTenant = tenant != nil;
    if (tenant) {
        _tenantName = IMJSONString(tenant[@"name"]);
        _isCustomer = [IMJSONString(data[@"kind"]) isEqualToString:@"customer"];
        _isCS = IMJSONBool(data[@"is_cs"]);
        _unitName = IMJSONString(IMJSONDict(data[@"unit"])[@"name"]);
        _deptName = IMJSONString(IMJSONDict(data[@"dept"])[@"name"]);
        _bindings = [IMTenantUnit unitsFromArray:data[@"bindings"]];
        _noticePending = IMJSONBool(data[@"notice_pending"]);
    }
    // 集团身份真的变了（加入 / 脱离；不含冷启动首拉）：入口开关在 server-config 里，跟着重拉一次。
    if (wasLoaded && hadTenant != _hasTenant) { [IMServerConfigStore.shared refreshNow]; }
    IMLogWithTag(IMLogTagHTTP, @"directory_me_applied has_tenant=%d customer=%d cs=%d bindings=%lu notice=%d",
                 _hasTenant, _isCustomer, _isCS, (unsigned long)_bindings.count, _noticePending);
    [NSNotificationCenter.defaultCenter postNotificationName:IMTenantStoreDidChangeNotification object:nil];
    return YES;
}

- (void)markNoticeAcked {
    if (!_noticePending) { return; }
    _noticePending = NO;
    NSMutableDictionary *raw = [_raw mutableCopy];
    [raw removeObjectForKey:@"notice_pending"];
    _raw = raw;
    [NSNotificationCenter.defaultCenter postNotificationName:IMTenantStoreDidChangeNotification object:nil];
}

@end
