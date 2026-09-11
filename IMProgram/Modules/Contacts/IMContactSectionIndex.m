//  IMContactSectionIndex.m

#import "IMContactSectionIndex.h"
#import "IMUserCard.h"

@implementation IMContactSectionIndex {
    NSArray<NSString *> *_titles;                       // 分组字母，与 _buckets 同序
    NSArray<NSArray<IMUserCard *> *> *_buckets;         // 每组卡片（组内已排序）
}

- (instancetype)initWithCards:(NSArray<IMUserCard *> *)cards {
    NSArray<IMUserCard *> *safe = cards ?: @[];
    return [self initWithCards:safe displayNames:[IMContactSectionIndex displayNamesForCards:safe]];
}

/// 指定初始化：names 与 cards 同序。纯计算——**不读 card 的任何属性**，因此可以放到后台队列跑。
- (instancetype)initWithCards:(NSArray<IMUserCard *> *)cards displayNames:(NSArray<NSString *> *)names {
    if ((self = [super init])) {
        [self buildFromCards:cards displayNames:names];
    }
    return self;
}

+ (NSArray<NSString *> *)displayNamesForCards:(NSArray<IMUserCard *> *)cards {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:cards.count];
    for (IMUserCard *c in cards) { [names addObject:c.displayName ?: @""]; }
    return names;
}

+ (void)buildWithCards:(NSArray<IMUserCard *> *)cards completion:(void (^)(IMContactSectionIndex *))completion {
    if (!completion) { return; }
    NSArray<IMUserCard *> *snapshot = [cards ?: @[] copy];
    // 显示名在调用线程取：displayName 读 IMRemarkStore（其 currentOwner 又去问 IMDatabase），
    // 留在主线程读，就不必论证这两把锁搬到后台线程后的锁序。2000 人取一遍只是字典查找，毫秒内。
    NSArray<NSString *> *names = [self displayNamesForCards:snapshot];
    dispatch_async([self buildQueue], ^{
        IMContactSectionIndex *index = [[IMContactSectionIndex alloc] initWithCards:snapshot displayNames:names];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(index); });
    });
}

/// 串行：连发的构建按发起顺序完成，调用方只需丢弃「不是最后一次发起」的结果。
+ (dispatch_queue_t)buildQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("im.contacts.index", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

- (void)buildFromCards:(NSArray<IMUserCard *> *)cards displayNames:(NSArray<NSString *> *)names {
    // 每张卡预计算全串拼音（保留音节空格）作分桶键与组内排序键，避免在比较器里反复 transform。
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *map = [NSMutableDictionary dictionary];
    [cards enumerateObjectsUsingBlock:^(IMUserCard *c, NSUInteger i, BOOL *stop) {
        NSString *name = i < names.count ? names[i] : @"";
        NSString *pinyin = [IMContactSectionIndex pinyinForName:name];
        NSString *key = [IMContactSectionIndex sectionKeyForName:name pinyin:pinyin]; // 复用上一行的拼音，别再转一遍
        NSMutableArray<NSDictionary *> *arr = map[key];
        if (!arr) { arr = [NSMutableArray array]; map[key] = arr; }
        [arr addObject:@{ @"card": c, @"pinyin": pinyin, @"name": name }];
    }];
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
        return [(NSString *)x[@"name"] localizedCaseInsensitiveCompare:(NSString *)y[@"name"]];
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

/// 拼音结果缓存。`CFStringTransform(MandarinLatin)` 是整条链路唯一的重活：2013 人转一遍约 130ms
/// （2026-09-11 Mac 实测；命中缓存 0.3ms），而名字在两次刷新之间几乎不变。
/// NSCache 线程安全（后台构建与主线程同步构建会同时读写），内存吃紧被系统回收也只是重算一次。
+ (NSCache<NSString *, NSString *> *)pinyinCache {
    static NSCache<NSString *, NSString *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 20000;
    });
    return cache;
}

/// 名字 → 全串拼音（小写，保留音节间空格）。中文转带调拼音再去声调；拉丁/数字原样透传。
+ (NSString *)pinyinForName:(NSString *)name {
    if (name.length == 0) { return @""; }
    NSString *cached = [[self pinyinCache] objectForKey:name];
    if (cached) { return cached; }
    NSMutableString *s = [name mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformMandarinLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformStripDiacritics, false);
    NSString *pinyin = [s lowercaseString];
    [[self pinyinCache] setObject:pinyin forKey:name];
    return pinyin;
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
    return [self sectionKeyForName:name pinyin:[self pinyinForName:name]];
}

/// pinyin 由调用方传入（分桶时已经算过）。原先这里自己再调一次 pinyinForName:，每人转换两遍。
+ (NSString *)sectionKeyForName:(NSString *)name pinyin:(NSString *)pinyin {
    if (name.length == 0) { return @"#"; }
    NSString *override = [self polyphonicSurnames][[name substringToIndex:1]]; // 多音姓氏优先归正确桶
    if (override) { return override; }
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
