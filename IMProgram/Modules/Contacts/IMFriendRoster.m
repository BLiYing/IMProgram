//  IMFriendRoster.m

#import "IMFriendRoster.h"
#import "IMFriendCacheWriter.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMLog.h"

@implementation IMFriendRoster

- (instancetype)initWithPending:(NSArray<IMUserCard *> *)pending accepted:(NSArray<IMUserCard *> *)accepted {
    self = [super init];
    if (self) {
        _pending = [pending copy];
        _accepted = [accepted copy];
    }
    return self;
}

+ (instancetype)rosterWithFriends:(NSArray<IMUserCard *> *)friends {
    NSMutableArray<IMUserCard *> *pending = [NSMutableArray array];
    NSMutableArray<IMUserCard *> *accepted = [NSMutableArray array];
    for (IMUserCard *card in friends) {
        if (card.status == IMFriendStatusPending) { [pending addObject:card]; }
        else if (card.status == IMFriendStatusAccepted) { [accepted addObject:card]; }
    }
    return [[self alloc] initWithPending:pending accepted:accepted];
}

+ (void)fetchWithHost:(NSString *)host userID:(NSString *)userID
              context:(IMDatabaseAccountContext *)context source:(NSString *)source
           completion:(void (^)(IMFriendRoster *, NSString *))completion {
    IMHTTPService.sharedService.host = host;
    [IMHTTPService.sharedService loginWithUserID:userID completion:^(NSString *token, NSError *error) {
        if (token.length == 0) {
            IMLog(@"%@ 好友名单刷新登录失败（保留当前内容）：%@", source, error.localizedDescription ?: @"未知错误");
            completion(nil, nil);
            return;
        }
        [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            if (err) {
                IMLog(@"%@ 好友名单刷新失败（保留当前内容）：%@", source, err.localizedDescription ?: @"未知错误");
                completion(nil, token);
                return;
            }
            IMFriendRoster *roster = [self rosterWithFriends:friends ?: @[]];
            [IMFriendCacheWriter persistFriendsIfChanged:roster.accepted context:context];
            completion(roster, token);
        }];
    }];
}

@end
