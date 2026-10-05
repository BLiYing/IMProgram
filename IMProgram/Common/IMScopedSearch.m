//  IMScopedSearch.m

#import "IMScopedSearch.h"
#import "IMGroupInfo.h"

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

NSArray<IMGroupInfo *> *IMScopedGroupHits(NSArray<IMGroupInfo *> *groups, NSString *keyword, NSString *fallbackName) {
    NSMutableArray<IMGroupInfo *> *out = [NSMutableArray array];
    for (IMGroupInfo *g in groups) {
        NSString *title = g.name.length > 0 ? g.name : fallbackName;
        if (IMScopedSearchMatches(keyword, @[title ?: @""])) { [out addObject:g]; }
    }
    return out;
}
