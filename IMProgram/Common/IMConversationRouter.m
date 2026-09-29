//  IMConversationRouter.m

#import "IMConversationRouter.h"

static void (^_opener)(NSString *, NSString *, IMConversation *);

@implementation IMConversationRouter

+ (void (^)(NSString *, NSString *, IMConversation *))opener {
    @synchronized (self) {
        return _opener;
    }
}

+ (void)setOpener:(void (^)(NSString *, NSString *, IMConversation *))opener {
    @synchronized (self) {
        _opener = [opener copy];
    }
}

+ (void)openConversation:(IMConversation *)conversation host:(NSString *)host userID:(NSString *)userID {
    if (!conversation) { return; }
    void (^opener)(NSString *, NSString *, IMConversation *) = self.opener;
    if (!opener) { return; } // 未注册（如 Modules/Chat 尚未加载）：静默返回，不崩溃
    opener(host, userID, conversation);
}

@end
