//  IMFriendPickerSelectAll.m

#import "IMFriendPickerSelectAll.h"

BOOL IMFriendPickerAllVisibleSelected(NSArray<NSString *> *selected, NSArray<NSString *> *visible) {
    if (visible.count == 0) { return NO; }
    NSSet<NSString *> *sel = [NSSet setWithArray:selected];
    for (NSString *uid in visible) {
        if (![sel containsObject:uid]) { return NO; }
    }
    return YES;
}

NSArray<NSString *> *IMFriendPickerNextSelection(NSArray<NSString *> *selected,
                                                  NSArray<NSString *> *visible,
                                                  NSInteger limit) {
    NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSetWithArray:selected];
    for (NSString *uid in visible) {
        if (limit > 0 && (NSInteger)out.count >= limit) { break; }
        if (uid.length > 0) { [out addObject:uid]; }
    }
    return out.array;
}

NSArray<NSString *> *IMFriendPickerDeselectVisible(NSArray<NSString *> *selected,
                                                    NSArray<NSString *> *visible) {
    NSSet<NSString *> *vis = [NSSet setWithArray:visible];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *uid in selected) {
        if (![vis containsObject:uid]) { [out addObject:uid]; }
    }
    return out;
}
