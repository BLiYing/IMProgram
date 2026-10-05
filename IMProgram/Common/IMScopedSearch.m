//  IMScopedSearch.m

#import "IMScopedSearch.h"

@implementation IMSettingsSearchEntry
+ (instancetype)entryWithId:(NSString *)rowId title:(NSString *)title systemImage:(NSString *)image {
    IMSettingsSearchEntry *e = [IMSettingsSearchEntry new];
    e.rowId = rowId; e.title = title; e.systemImage = image;
    return e;
}
@end

NSString *IMScopedSearchNormalize(NSString *keyword) {
    return [(keyword ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL IMScopedSearchMatches(NSString *keyword, NSArray<NSString *> *fields) {
    NSString *kw = IMScopedSearchNormalize(keyword);
    if (kw.length == 0) { return NO; }
    for (NSString *f in fields) {
        if (f.length > 0 && [f rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    return NO;
}

NSArray<IMSettingsSearchEntry *> *IMSettingsSearchFilter(NSArray<IMSettingsSearchEntry *> *entries, NSString *keyword) {
    NSMutableArray<IMSettingsSearchEntry *> *out = [NSMutableArray array];
    for (IMSettingsSearchEntry *e in entries) {
        if (IMScopedSearchMatches(keyword, @[e.title ?: @""])) { [out addObject:e]; }
    }
    return out;
}
