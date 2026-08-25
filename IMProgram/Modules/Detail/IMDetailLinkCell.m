//  IMDetailLinkCell.m
//  详情页链接 tab 单行：外层 cell 只负责外边距 (L16/R16/T9/B9)，卡片内容全由 IMLinkRowView 承担。
//  visual specs 参见草图 §C UI 规格表。

#import "IMDetailLinkCell.h"
#import "IMMessageModel.h"
#import "IMLinkRowView.h"
#import "IMMediaUtil.h"           // IMFormatFileDateTime

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
    [_row configureWithURL:message.content ?: @""
                  timeText:IMFormatFileDateTime(message.timestamp)];
}

@end
