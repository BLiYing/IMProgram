//  IMDeviceIdentity.m

#import "IMDeviceIdentity.h"
#import <UIKit/UIKit.h>

static NSString * const kIMDeviceIDKey = @"im_device_id";

@implementation IMDeviceIdentity

+ (NSString *)deviceID {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *existing = [d stringForKey:kIMDeviceIDKey];
    if (existing.length > 0) { return existing; }
    // 首次：生成并持久化一枚随机 UUID（去掉横杠更短，仍 >128bit 唯一）。
    NSString *fresh = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    [d setObject:fresh forKey:kIMDeviceIDKey];
    [d synchronize];
    return fresh;
}

+ (NSString *)platform { return @"ios"; }

+ (NSString *)deviceName {
    NSString *name = UIDevice.currentDevice.name;
    return name.length > 0 ? name : @"iPhone";
}

+ (NSString *)appVersion {
    NSString *v = [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleShortVersionString"];
    return [v isKindOfClass:NSString.class] ? v : @"";
}

@end
