//  IMChatPresence.m

#import "IMChatPresence.h"

static NSString *_currentViewingConvID;

@implementation IMChatPresence

+ (void)noteViewingConvID:(NSString *)convID {
    @synchronized (self) {
        _currentViewingConvID = [convID copy];
    }
}

+ (void)clearViewingConvIDIfCurrent:(NSString *)convID {
    @synchronized (self) {
        if ([_currentViewingConvID isEqualToString:convID]) {
            _currentViewingConvID = nil;
        }
    }
}

+ (nullable NSString *)currentViewingConvID {
    @synchronized (self) {
        return _currentViewingConvID;
    }
}

@end
