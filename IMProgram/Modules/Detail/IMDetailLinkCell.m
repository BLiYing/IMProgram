//  IMDetailLinkCell.m
//  详情页链接 tab 单行：外层 cell 只负责外边距 (L16/R16/T9/B9)，卡片内容全由 IMLinkRowView 承担。
//  visual specs 参见草图 §C UI 规格表。

#import "IMDetailLinkCell.h"
#import "IMMessageModel.h"
#import "IMLinkRowView.h"
#import "IMMediaUtil.h"           // IMFirstURLInText / IMFormatFileDateTime

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
    // 时间用「年月日 时:分」完整口径（IMFormatFileDateTime）——与本页文件/语音/名片 tab 一致。
    // 曾用「今日 HH:mm / 昨天 HH:mm / M月d日」的紧凑格式：同一页四个 tab 两套时间语言，
    // 且跨年记录只剩「3月2日」看不出哪一年（用户反馈）。Web `detailFullDateTime` 同步拉齐。
    [_row configureWithURL:url timeText:(message.timestamp > 0 ? IMFormatFileDateTime(message.timestamp) : @"")];
}

@end
