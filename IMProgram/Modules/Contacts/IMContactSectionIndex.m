//  IMContactSectionIndex.m

#import "IMContactSectionIndex.h"
#import "IMUserCard.h"

@implementation IMContactSectionIndex {
    NSArray<NSString *> *_titles;                       // 分组字母，与 _buckets 同序
    NSArray<NSArray<IMUserCard *> *> *_buckets;         // 每组卡片（组内已排序）
}

- (instancetype)initWithCards:(NSArray<IMUserCard *> *)cards {
    if ((self = [super init])) {
        [self buildFromCards:cards ?: @[]];
    }
    return self;
}

- (void)buildFromCards:(NSArray<IMUserCard *> *)cards {
    // 每张卡预计算全串拼音（保留音节空格）作分桶键与组内排序键，避免在比较器里反复 transform。
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *map = [NSMutableDictionary dictionary];
    for (IMUserCard *c in cards) {
        NSString *name = c.displayName;
        NSString *pinyin = [IMContactSectionIndex pinyinForName:name];
        NSString *key = [IMContactSectionIndex sectionKeyForName:name];
        NSMutableArray<NSDictionary *> *arr = map[key];
        if (!arr) { arr = [NSMutableArray array]; map[key] = arr; }
        [arr addObject:@{ @"card": c, @"pinyin": pinyin ?: @"" }];
    }
    // 标题排序：A–Z 升序在前，"#" 恒在最后。
    NSArray<NSString *> *keys = [map.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL ah = [a isEqualToString:@"#"], bh = [b isEqualToString:@"#"];
        if (ah != bh) { return ah ? NSOrderedDescending : NSOrderedAscending; }
        return [a compare:b];
    }];
    // 组内按全串拼音升序（带音节空格，空格 ASCII 低 → 天然保证「姓在前」：李 li< 林 lin< 刘 liu）；
    // 拼音相同再退回显示名兜底。
    NSComparator entryCmp = ^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        NSComparisonResult r = [(NSString *)x[@"pinyin"] compare:(NSString *)y[@"pinyin"]];
        if (r != NSOrderedSame) { return r; }
        return [[(IMUserCard *)x[@"card"] displayName] localizedCaseInsensitiveCompare:[(IMUserCard *)y[@"card"] displayName]];
    };
    NSMutableArray<NSArray<IMUserCard *> *> *buckets = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *k in keys) {
        NSArray<NSDictionary *> *sorted = [map[k] sortedArrayUsingComparator:entryCmp];
        NSMutableArray<IMUserCard *> *bucket = [NSMutableArray arrayWithCapacity:sorted.count];
        for (NSDictionary *e in sorted) { [bucket addObject:e[@"card"]]; }
        [buckets addObject:bucket];
    }
    _titles = keys;
    _buckets = buckets;
}

/// 名字 → 全串拼音（小写，保留音节间空格）。中文转带调拼音再去声调；拉丁/数字原样透传。
+ (NSString *)pinyinForName:(NSString *)name {
    if (name.length == 0) { return @""; }
    NSMutableString *s = [name mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformMandarinLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformStripDiacritics, false);
    return [s lowercaseString];
}

/// 常见多音姓氏 → 正确分组首字母（普通话默认拼音会取错读音的那些）。非穷举，覆盖高频姓。
+ (NSDictionary<NSString *, NSString *> *)polyphonicSurnames {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"曾": @"Z", @"仇": @"Q", @"单": @"S", @"解": @"X", @"查": @"Z",
                 @"区": @"O", @"乐": @"Y", @"翟": @"Z", @"覃": @"Q", @"秘": @"B" };
    });
    return map;
}

+ (NSString *)sectionKeyForName:(NSString *)name {
    if (name.length == 0) { return @"#"; }
    NSString *override = [self polyphonicSurnames][[name substringToIndex:1]]; // 多音姓氏优先归正确桶
    if (override) { return override; }
    NSString *pinyin = [self pinyinForName:name];
    if (pinyin.length == 0) { return @"#"; }
    unichar c = [[pinyin uppercaseString] characterAtIndex:0];
    if (c >= 'A' && c <= 'Z') { return [NSString stringWithFormat:@"%C", c]; }
    return @"#";
}

- (NSInteger)numberOfSections { return (NSInteger)_titles.count; }

- (NSInteger)numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)_buckets.count) { return 0; }
    return (NSInteger)_buckets[section].count;
}

- (NSString *)titleForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)_titles.count) { return @""; }
    return _titles[section];
}

- (IMUserCard *)cardAtSection:(NSInteger)section row:(NSInteger)row {
    if (section < 0 || section >= (NSInteger)_buckets.count) { return nil; }
    NSArray<IMUserCard *> *arr = _buckets[section];
    if (row < 0 || row >= (NSInteger)arr.count) { return nil; }
    return arr[row];
}

@end
