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

/// 搜索框本体高度：容器 56 内垂直居中，上下各留 6。
static const CGFloat kIMListSearchFieldHeight = 44;

UIView *IMListSearchHeaderMake(UISearchBar *bar) {
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bar.frame.size.width, kIMListSearchBarHeight)];
    host.backgroundColor = UIColor.clearColor;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [bar.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [bar.heightAnchor constraintEqualToConstant:kIMListSearchFieldHeight],
    ]];
    return host;
}

void IMListSearchHeaderSyncWidth(UIView *header, UITableView *table) {
    if (!header || !table) { return; }
    CGFloat width = table.bounds.size.width;
    // 宽度已一致就早退：viewDidLayoutSubviews 每次布局都会调它，不早退则「改 frame → 触发布局」自激。
    if (width <= 0 || fabs(CGRectGetWidth(header.frame) - width) < 0.5) { return; }
    header.frame = CGRectMake(0, 0, width, kIMListSearchBarHeight);
    [header layoutIfNeeded];
    table.tableHeaderView = header;
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
