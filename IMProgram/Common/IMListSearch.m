//  IMListSearch.m

#import "IMListSearch.h"

/// 搜索框高度：56 = 输入框本体 + 上下留白，挂 tableHeaderView 时与首行不粘连。
static const CGFloat kIMListSearchBarHeight = 56;

UISearchBar *IMListSearchBarMake(CGFloat width, NSString *placeholder, id<UISearchBarDelegate> delegate) {
    UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, width, kIMListSearchBarHeight)];
    bar.placeholder = placeholder;
    bar.delegate = delegate;
    bar.searchBarStyle = UISearchBarStyleMinimal; // 无灰底方块，融进列表背景
    bar.autocorrectionType = UITextAutocorrectionTypeNo;
    bar.autocapitalizationType = UITextAutocapitalizationTypeNone; // 搜 uid 时别被首字母大写改坏
    return bar;
}

NSString *IMListSearchNormalizedQuery(NSString *raw) {
    return [(raw ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL IMListSearchMatches(NSString *query, NSArray<NSString *> *fields) {
    NSString *q = IMListSearchNormalizedQuery(query);
    if (q.length == 0) { return YES; } // 没在搜 = 全部命中
    for (NSString *f in fields) {
        if (![f isKindOfClass:NSString.class] || f.length == 0) { continue; }
        if ([f rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    return NO;
}
