//  IMConversationRouter.m

#import "IMConversationRouter.h"

static BOOL (^_opener)(NSString *, NSString *, IMConversation *);

@implementation IMConversationRouter

+ (BOOL (^)(NSString *, NSString *, IMConversation *))opener {
    @synchronized (self) {
        return _opener;
    }
}

+ (void)setOpener:(BOOL (^)(NSString *, NSString *, IMConversation *))opener {
    @synchronized (self) {
        _opener = [opener copy];
    }
}

+ (BOOL)openConversation:(IMConversation *)conversation host:(NSString *)host userID:(NSString *)userID {
    if (!conversation) { return NO; }
    BOOL (^opener)(NSString *, NSString *, IMConversation *) = self.opener;
    if (!opener) { return NO; } // 未注册（如 Modules/Chat 尚未加载）：静默返回，不崩溃
    return opener(host, userID, conversation);
}

@end
