//  IMReconnectReloader.m

#import "IMReconnectReloader.h"
#import "IMSocketManager.h"

@implementation IMReconnectReloader {
    dispatch_block_t _reload;
}

- (instancetype)initWithReloadBlock:(dispatch_block_t)reloadBlock {
    if ((self = [super init])) {
        _reload = [reloadBlock copy];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketState:)
                                                   name:IMSocketDidChangeStateNotification object:nil];
    }
    return self;
}

- (void)onSocketState:(NSNotification *)note {
    IMSocketState state = (IMSocketState)[note.userInfo[@"state"] integerValue];
    // 连接恢复即取权威数据；失败由宿主 reload 自行保留缓存种子、不弹窗。
    if (state == IMSocketStateConnected && _visible && _reload) { _reload(); }
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
