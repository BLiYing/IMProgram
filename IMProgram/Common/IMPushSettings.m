//  IMPushSettings.m

#import "IMPushSettings.h"

NSNotificationName const IMPushSettingsDidChangeNotification = @"IMPushSettingsDidChangeNotification";

static NSString * const kIMPushReceiveOfflineKey = @"im.push.receiveOffline";

@implementation IMPushSettings

+ (instancetype)shared {
    static IMPushSettings *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [IMPushSettings new]; });
    return value;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _receiveOfflinePush = [d objectForKey:kIMPushReceiveOfflineKey] ? [d boolForKey:kIMPushReceiveOfflineKey] : YES;
    }
    return self;
}

- (void)setReceiveOfflinePush:(BOOL)receiveOfflinePush {
    if (_receiveOfflinePush == receiveOfflinePush) { return; }
    _receiveOfflinePush = receiveOfflinePush;
    [NSUserDefaults.standardUserDefaults setBool:receiveOfflinePush forKey:kIMPushReceiveOfflineKey];
    [NSNotificationCenter.defaultCenter postNotificationName:IMPushSettingsDidChangeNotification object:self];
}

@end
