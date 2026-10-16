//  IMChatFolderStore.m

#import "IMChatFolderStore.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Folders.h"
#import "IMSocketManager.h"
#import "IMSocketManager+Push.h"
#import "IMLocalization.h"
#import "IMLog.h"

NSNotificationName const IMChatFoldersDidChangeNotification = @"IMChatFoldersDidChangeNotification";

static NSString * const kIMChatFoldersDefaultsPrefix = @"im.chatFolders.";
static NSInteger const kDefaultMaxFolders = 10;
static NSInteger const kDefaultMaxConvs = 100;
static NSInteger const kDefaultMaxName = 12;

@implementation IMChatFolderStore {
    NSString *_ownerUID;
    NSArray<IMChatFolder *> *_folders;
    int64_t _version;
    NSInteger _maxFolders, _maxConvs, _maxName;
    BOOL _started;
    BOOL _refreshing;
}

+ (instancetype)shared {
    static IMChatFolderStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMChatFolderStore new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _folders = @[];
        _maxFolders = kDefaultMaxFolders; _maxConvs = kDefaultMaxConvs; _maxName = kDefaultMaxName;
    }
    return self;
}

- (NSArray<IMChatFolder *> *)folders { return _folders; }
- (int64_t)version { return _version; }
- (NSInteger)maxFolders { return _maxFolders; }
- (NSInteger)maxConvs { return _maxConvs; }
- (NSInteger)maxNameLength { return _maxName; }

#pragma mark - 生命周期

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(onSocketStateChanged:) name:IMSocketDidChangeStateNotification object:nil];
    [nc addObserver:self selector:@selector(onFolderFrame:) name:IMSocketDidReceiveFolderUpdateNotification object:nil];
    [self refresh];
}

- (void)onSocketStateChanged:(NSNotification *)note {
    // 重连后补一次（断线期间可能错过帧）；版本不变则 applySnapshot 空转。
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

- (void)onFolderFrame:(NSNotification *)note {
    if (![note.userInfo isKindOfClass:NSDictionary.class]) { return; }
    [self adoptUserID:IMSocketManager.sharedManager.userID];
    [self applySnapshot:note.userInfo];
}

- (void)adoptUserID:(NSString *)userID {
    if (userID.length == 0 || [userID isEqualToString:_ownerUID]) { return; }
    _ownerUID = [userID copy];
    _folders = @[]; _version = 0;
    _maxFolders = kDefaultMaxFolders; _maxConvs = kDefaultMaxConvs; _maxName = kDefaultMaxName;
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:[self defaultsKey]];
    if (saved) { [self applySnapshot:saved persist:NO]; }
    [self postChange];
}

- (NSString *)defaultsKey { return [kIMChatFoldersDefaultsPrefix stringByAppendingString:_ownerUID ?: @""]; }

- (void)postChange {
    [NSNotificationCenter.defaultCenter postNotificationName:IMChatFoldersDidChangeNotification object:self];
}

#pragma mark - 读

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || _refreshing) { return; } // 未登录：登录后 socket 连上会再触发
    [self adoptUserID:IMSocketManager.sharedManager.userID];
    _refreshing = YES;
    NSString *askedFor = [_ownerUID copy]; // 回包时已换号则丢弃：别把上一个账号的整表写进新账号
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService foldersWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_refreshing = NO;
        if (![self->_ownerUID ?: @"" isEqualToString:askedFor ?: @""]) { return; }
        if (error || !data) {
            if (error) { IMLogWarnWithTag(IMLogTagApp, @"folders_fetch_failed code=%ld", (long)error.code); }
            return; // 失败保留本地缓存，下次重连 / 进页再试
        }
        [self applySnapshot:data];
    }];
}

- (nullable IMChatFolder *)folderWithID:(NSString *)folderID {
    for (IMChatFolder *f in _folders) {
        if ([f.folderID isEqualToString:folderID]) { return f; }
    }
    return nil;
}

- (NSArray<IMChatFolder *> *)foldersContainingConv:(NSString *)convID {
    NSMutableArray<IMChatFolder *> *out = [NSMutableArray array];
    for (IMChatFolder *f in _folders) {
        if ([f containsConv:convID]) { [out addObject:f]; }
    }
    return out;
}

#pragma mark - 整表替换

- (BOOL)applySnapshot:(NSDictionary *)data { return [self applySnapshot:data persist:YES]; }

- (BOOL)applySnapshot:(NSDictionary *)data persist:(BOOL)persist {
    if (![data isKindOfClass:NSDictionary.class] || ![data[@"folders"] isKindOfClass:NSArray.class]) { return NO; }
    // 上限随任何回包更新（即使整表版本没推进：GET 回 version 0 的空表也带着 limits）。
    NSDictionary *limits = [data[@"limits"] isKindOfClass:NSDictionary.class] ? data[@"limits"] : nil;
    if (limits) {
        if ([limits[@"max_folders"] integerValue] > 0) { _maxFolders = [limits[@"max_folders"] integerValue]; }
        if ([limits[@"max_convs"] integerValue] > 0) { _maxConvs = [limits[@"max_convs"] integerValue]; }
        if ([limits[@"max_name"] integerValue] > 0) { _maxName = [limits[@"max_name"] integerValue]; }
    }
    int64_t version = [data[@"version"] longLongValue];
    // 同版本 / 更旧：丢弃（PUT/POST 响应与同版本帧、乱序到达的旧帧都走这里）。
    if (version <= _version) { return NO; }
    NSMutableArray<IMChatFolder *> *list = [NSMutableArray array];
    for (id raw in data[@"folders"]) {
        IMChatFolder *f = [IMChatFolder folderFromJSON:raw];
        if (f) { [list addObject:f]; }
    }
    [list sortUsingComparator:^NSComparisonResult(IMChatFolder *a, IMChatFolder *b) {
        return a.position < b.position ? NSOrderedAscending : (a.position > b.position ? NSOrderedDescending : NSOrderedSame);
    }];
    _folders = list;
    _version = version;
    if (persist && _ownerUID.length > 0) {
        NSMutableArray *json = [NSMutableArray array];
        for (IMChatFolder *f in list) { [json addObject:f.toJSON]; }
        [NSUserDefaults.standardUserDefaults setObject:@{ @"version": @(version), @"folders": json } forKey:[self defaultsKey]];
    }
    if (persist) { [self postChange]; }
    return YES;
}

#pragma mark - 写

/// 写操作公共骨架：取 token → 发请求 → 成功整表替换。token 缺失按"未登录"失败。
- (void)perform:(void (^)(NSString *token, IMFolderCompletion done))call
     completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        NSError *e = [NSError errorWithDomain:@"IMChatFolder" code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey: IMLocalized(@"folder.toast.failed") }];
        completion(nil, e);
        return;
    }
    [self adoptUserID:IMSocketManager.sharedManager.userID];
    __weak typeof(self) ws = self;
    call(token, ^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (self && !error && data) { [self applySnapshot:data]; }
        completion(data, error);
    });
}

- (void)createFolderNamed:(NSString *)name convIDs:(NSArray<NSString *> *)convIDs
               completion:(void (^)(IMChatFolder *, NSError *))completion {
    // client_id：网络重发时服务端回既存结果而非报重名（PROTOCOL §11）。
    NSString *clientID = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    __weak typeof(self) ws = self;
    [self perform:^(NSString *token, IMFolderCompletion done) {
        [IMHTTPService.sharedService createFolderWithToken:token name:name convIDs:convIDs clientID:clientID completion:done];
    } completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        IMChatFolder *created = nil;
        if (!error && self) {
            // 按 client_id 派生的 id（"f_"+clientID）或名称找回刚建的那个。
            NSString *wantID = [@"f_" stringByAppendingString:clientID];
            created = [self folderWithID:wantID];
            if (!created) {
                for (IMChatFolder *f in self.folders) {
                    if ([f.name caseInsensitiveCompare:name] == NSOrderedSame) { created = f; break; }
                }
            }
        }
        completion(created, error);
    }];
}

- (void)renameFolder:(NSString *)folderID to:(NSString *)name completion:(void (^)(NSError *))completion {
    [self perform:^(NSString *token, IMFolderCompletion done) {
        [IMHTTPService.sharedService renameFolderWithToken:token folderID:folderID name:name completion:done];
    } completion:^(NSDictionary *data, NSError *error) { completion(error); }];
}

- (void)deleteFolder:(NSString *)folderID completion:(void (^)(NSError *))completion {
    [self perform:^(NSString *token, IMFolderCompletion done) {
        [IMHTTPService.sharedService deleteFolderWithToken:token folderID:folderID completion:done];
    } completion:^(NSDictionary *data, NSError *error) { completion(error); }];
}

- (void)reorderFolderIDs:(NSArray<NSString *> *)ids completion:(void (^)(NSError *))completion {
    [self perform:^(NSString *token, IMFolderCompletion done) {
        [IMHTTPService.sharedService reorderFoldersWithToken:token folderIDs:ids completion:done];
    } completion:^(NSDictionary *data, NSError *error) { completion(error); }];
}

- (void)changeConvsInFolder:(NSString *)folderID add:(NSArray<NSString *> *)add remove:(NSArray<NSString *> *)remove
                 completion:(void (^)(NSError *))completion {
    [self perform:^(NSString *token, IMFolderCompletion done) {
        [IMHTTPService.sharedService changeFolderConvsWithToken:token folderID:folderID add:add remove:remove completion:done];
    } completion:^(NSDictionary *data, NSError *error) { completion(error); }];
}

#pragma mark - 文案 / 测试

+ (NSString *)userMessageForError:(NSError *)error {
    NSInteger code = error.code;
    if (code >= 300301 && code <= 300305) {
        NSString *key = [NSString stringWithFormat:@"err.%ld", (long)code];
        return IMLocalized(key); // 宏参数里不能直接带逗号表达式，先落变量
    }
    return error.localizedDescription.length > 0 ? error.localizedDescription : IMLocalized(@"folder.toast.failed");
}

- (void)resetForTesting { [self wipeLocalState]; }

- (void)wipeLocalState {
    if (_ownerUID.length > 0) { [NSUserDefaults.standardUserDefaults removeObjectForKey:[self defaultsKey]]; }
    _ownerUID = nil; _folders = @[]; _version = 0;
    _maxFolders = kDefaultMaxFolders; _maxConvs = kDefaultMaxConvs; _maxName = kDefaultMaxName;
}

@end
