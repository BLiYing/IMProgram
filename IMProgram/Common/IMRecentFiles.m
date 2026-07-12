//  IMRecentFiles.m

#import "IMRecentFiles.h"

static const NSUInteger kIMRecentFilesCap = 20;

@implementation IMRecentFiles

+ (NSString *)keyForOwner:(NSString *)ownerID {
    return [@"im_recent_files_" stringByAppendingString:(ownerID.length ? ownerID : @"_")];
}

+ (void)recordForOwner:(NSString *)ownerID url:(NSString *)url name:(NSString *)name {
    if (url.length == 0) { return; }
    NSString *key = [self keyForOwner:ownerID];
    NSMutableArray<NSDictionary *> *list = [[NSUserDefaults.standardUserDefaults arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    // 去重（同 url 移除旧项）
    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
    for (NSDictionary *it in list) {
        if (![[it[@"url"] description] isEqualToString:url]) { [filtered addObject:it]; }
    }
    [filtered insertObject:@{ @"url": url, @"name": (name ?: url) } atIndex:0];
    while (filtered.count > kIMRecentFilesCap) { [filtered removeLastObject]; }
    [NSUserDefaults.standardUserDefaults setObject:filtered forKey:key];
}

+ (NSArray<NSDictionary *> *)listForOwner:(NSString *)ownerID {
    return [NSUserDefaults.standardUserDefaults arrayForKey:[self keyForOwner:ownerID]] ?: @[];
}

@end
