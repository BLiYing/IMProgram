//  IMNetworkMonitor.m

#import "IMNetworkMonitor.h"
#import <Network/Network.h>

@implementation IMNetworkMonitor {
    nw_path_monitor_t _monitor;
    IMNetworkType _currentType;
    BOOL _started;
}

+ (instancetype)shared {
    static IMNetworkMonitor *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMNetworkMonitor new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) { _currentType = IMNetworkTypeWifi; } // 首帧前乐观：不误伤默认自动下载
    return self;
}

- (IMNetworkType)currentType { return _currentType; }

- (void)start {
    if (_started) { return; }
    _started = YES;
    _monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_monitor, dispatch_get_main_queue());
    __weak IMNetworkMonitor *ws = self;
    nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t path) {
        __strong IMNetworkMonitor *self = ws;
        if (!self) { return; }
        if (nw_path_get_status(path) != nw_path_status_satisfied) {
            self->_currentType = IMNetworkTypeNone;
        } else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
            self->_currentType = IMNetworkTypeCellular;
        } else {
            self->_currentType = IMNetworkTypeWifi; // Wi-Fi / 有线 / 其它一律按不限流量
        }
    });
    nw_path_monitor_start(_monitor);
}

@end
