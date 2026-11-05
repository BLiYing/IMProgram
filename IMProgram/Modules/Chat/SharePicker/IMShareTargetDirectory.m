//  IMShareTargetDirectory.m

#import "IMShareTargetDirectory.h"
#import "IMShareSelection.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMLog.h"

@implementation IMShareTargetDirectory {
    NSString *_token;
    NSString *_selfUID;
    NSMutableArray<void (^)(void)> *_waiters;
    NSDictionary<NSString *, IMConversation *> *_friendByUID;
    NSSet<NSString *> *_excluded;
    NSSet<NSString *> *_excludedConvs;
}

- (instancetype)initWithToken:(NSString *)token selfUID:(NSString *)selfUID
              excludedUserIDs:(NSSet<NSString *> *)excludedUserIDs excludedConvIDs:(NSSet<NSString *> *)excludedConvIDs {
    if ((self = [super init])) {
        _excluded = [excludedUserIDs copy] ?: [NSSet set];
        _excludedConvs = [excludedConvIDs copy] ?: [NSSet set];
        _token = [token copy];
        _selfUID = [selfUID copy];
        _waiters = [NSMutableArray array];
        _friendCards = @[];
        _groupTargets = @[];
    }
    return self;
}

- (void)loadIfNeeded:(void (^)(void))completion {
    if (_loaded) { if (completion) { completion(); } return; }
    if (completion) { [_waiters addObject:[completion copy]]; }
    if (_loading) { return; }
    _loading = YES;

    dispatch_group_t group = dispatch_group_create();
    __block NSArray<IMUserCard *> *friends = nil;
    __block NSArray<IMGroupInfo *> *groups = nil;
    __block BOOL friendsFailed = NO, groupsFailed = NO;

    dispatch_group_enter(group);
    [IMHTTPService.sharedService friendsWithToken:_token status:@"accepted"
                                       completion:^(NSArray<IMUserCard *> *list, NSError *error) {
        if (error) { IMLogWithTag(IMLogTagUI, @"share picker 拉好友失败：%@", error.localizedDescription); friendsFailed = YES; }
        friends = list ?: @[];
        dispatch_group_leave(group);
    }];
    dispatch_group_enter(group);
    [IMHTTPService.sharedService groupsWithToken:_token completion:^(NSArray<IMGroupInfo *> *list, NSError *error) {
        if (error) { IMLogWithTag(IMLogTagUI, @"share picker 拉群列表失败：%@", error.localizedDescription); groupsFailed = YES; }
        groups = list ?: @[];
        dispatch_group_leave(group);
    }];

    __weak typeof(self) ws = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self applyFriends:friends groups:groups];
        self->_friendsFailed = friendsFailed;
        self->_groupsFailed = groupsFailed;
        self->_loading = NO;
        // 失败的那一路不算「已加载」：下次进子页 / 搜索会再试一次，而不是永远空着。
        self->_loaded = !friendsFailed && !groupsFailed;
        NSArray<void (^)(void)> *waiters = [self->_waiters copy];
        [self->_waiters removeAllObjects];
        for (void (^w)(void) in waiters) { w(); }
    });
}

- (void)applyFriends:(NSArray<IMUserCard *> *)friends groups:(NSArray<IMGroupInfo *> *)groups {
    NSMutableArray<IMUserCard *> *cards = [NSMutableArray arrayWithCapacity:friends.count];
    NSMutableDictionary<NSString *, IMConversation *> *byUID = [NSMutableDictionary dictionary];
    for (IMUserCard *card in friends) {
        if (![IMShareSelection isShareableFriend:card] || [_excluded containsObject:card.userID]) { continue; }
        IMConversation *c = [IMShareSelection conversationForFriend:card selfUID:_selfUID];
        if (!c || byUID[card.userID] || [_excludedConvs containsObject:c.convID]) { continue; }
        [cards addObject:card];
        byUID[card.userID] = c;
    }
    _friendCards = cards;
    _friendByUID = byUID;

    NSMutableArray<IMConversation *> *groupTargets = [NSMutableArray arrayWithCapacity:groups.count];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (IMGroupInfo *g in groups) {
        IMConversation *c = [IMShareSelection conversationForGroup:g];
        if (!c || [seen containsObject:c.convID] || [_excludedConvs containsObject:c.convID]) { continue; }
        [seen addObject:c.convID];
        [groupTargets addObject:c];
    }
    _groupTargets = groupTargets;
}

- (IMConversation *)targetForFriend:(IMUserCard *)card {
    if (card.userID.length == 0) { return nil; }
    return _friendByUID[card.userID] ?: [IMShareSelection conversationForFriend:card selfUID:_selfUID];
}

@end
