//  IMChatPresence.m

#import "IMChatPresence.h"

NSNotificationName const IMChatPresenceDidChangeNotification = @"IMChatPresenceDidChangeNotification";
NSString * const IMChatPresenceConvIDKey = @"convID";

static NSString *_currentViewingConvID;

@implementation IMChatPresence

+ (void)noteViewingConvID:(NSString *)convID {
    @synchronized (self) {
        _currentViewingConvID = [convID copy];
    }
    // 广播放主线程：聊天页的 viewDidAppear 本就在主线程调用本方法，这里不再额外 dispatch，
    // 与 noteViewingConvID 的调用方（UIKit 生命周期回调）同步发生，避免时序滞后。
    [NSNotificationCenter.defaultCenter postNotificationName:IMChatPresenceDidChangeNotification object:nil
                                                     userInfo:convID ? @{IMChatPresenceConvIDKey: convID} : @{}];
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
