//  IMDetailLinkCell.m
//  详情页链接 tab 单行：外层 cell 只负责外边距 (L16/R16/T9/B9)，卡片内容全由 IMLinkRowView 承担。
//  visual specs 参见草图 §C UI 规格表。

#import "IMDetailLinkCell.h"
#import "IMMessageModel.h"
#import "IMLinkRowView.h"
#import "IMMediaUtil.h"           // IMFirstURLInText

/// 详情页/收藏页链接行时间格式（与 Web `detailLinkTimeText` 对齐）：今日 HH:mm / 昨天 HH:mm / M月d日。
/// 不用 `IMFormatFileDateTime`（那个是 yyyy-MM-dd HH:mm 太长，草图 §C 明确要求紧凑格式）。
static NSString *IMDetailLinkTimeText(int64_t timestampMillis) {
    if (timestampMillis <= 0) { return @""; }
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestampMillis / 1000.0];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    NSDate *dayOfD = [cal startOfDayForDate:d];
    NSDateComponents *diff = [cal components:NSCalendarUnitDay fromDate:dayOfD toDate:today options:0];
    static NSDateFormatter *hm = nil, *md = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        hm = [NSDateFormatter new]; hm.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; hm.dateFormat = @"HH:mm";
        md = [NSDateFormatter new]; md.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; md.dateFormat = @"M月d日";
    });
    if (diff.day == 0) { return [hm stringFromDate:d]; }
    if (diff.day == 1) { return [NSString stringWithFormat:@"昨天 %@", [hm stringFromDate:d]]; }
    return [md stringFromDate:d];
}

@implementation IMDetailLinkCell {
    IMLinkRowView *_row;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _row = [IMLinkRowView new];
        _row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_row];
        [NSLayoutConstraint activateConstraints:@[
            [_row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [_row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message {
    // 混排文本"看看 https://foo.com/ 好文"：只把首个 URL 交给 IMLinkRowView，否则把整段中文喂给
    // preview API → 404（与 Web DetailTabs.tsx 同款抽取，两端口径一致）。
    NSString *content = message.content ?: @"";
    NSString *url = IMFirstURLInText(content) ?: content;
    [_row configureWithURL:url timeText:IMDetailLinkTimeText(message.timestamp)];
}

@end
