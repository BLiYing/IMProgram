//  IMChatRecordViewController.m

#import "IMChatRecordViewController.h"
#import <SafariServices/SafariServices.h>
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "IMMediaViewerViewController.h"

// 记录预览/标题解析统一走 IMMediaUtil 的 IMSummarizeRecord/IMRecordItemPreview（含嵌套 chat_record→[聊天记录] 子标题），
// 与气泡卡片 IMChatRecordCell 共用同一 token 映射，避免各持 static 分叉。

#pragma mark - 单条记录 Cell

@interface IMRecordItemCell : UITableViewCell
- (void)configureWithName:(NSString *)name type:(NSString *)type content:(NSString *)content fullURL:(NSString *)fullURL
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize caption:(nullable NSString *)caption;
@end

@implementation IMRecordItemCell {
    UILabel *_name;
    UILabel *_text;
    UILabel *_caption;      // 图说条目「有字显字」：媒体/文件下方随附文本
    UIImageView *_thumb;
    UIImageView *_playBadge;
    NSString *_thumbURL;
    UIView  *_recCard;      // 嵌套合并转发：套娃 mini 卡片（标题 + 2 行预览 + 「聊天记录 ›」脚注）
    UILabel *_recTitle;
    UILabel *_recPreview;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _name = [UILabel new];
        _name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _name.textColor = UIColor.secondaryLabelColor;

        _text = [UILabel new];
        _text.font = [UIFont systemFontOfSize:16];
        _text.textColor = UIColor.labelColor;
        _text.numberOfLines = 0;

        _caption = [UILabel new];
        _caption.font = [UIFont systemFontOfSize:15];
        _caption.textColor = UIColor.labelColor;
        _caption.numberOfLines = 0;
        _caption.hidden = YES;

        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 8;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        [_thumb.widthAnchor constraintEqualToConstant:200].active = YES;
        [_thumb.heightAnchor constraintEqualToConstant:140].active = YES;

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = UIColor.whiteColor;
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [_thumb addSubview:_playBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
        ]];

        // 嵌套合并转发条目 → 套娃 mini 卡片（描边圆角、比外层窄；整行点击下钻，见 didSelectRow）。
        _recCard = [UIView new];
        _recCard.translatesAutoresizingMaskIntoConstraints = NO;
        _recCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _recCard.layer.cornerRadius = 10;
        _recCard.layer.borderWidth = 0.5;
        _recCard.layer.borderColor = UIColor.separatorColor.CGColor;
        _recTitle = [UILabel new];
        _recTitle.translatesAutoresizingMaskIntoConstraints = NO;
        _recTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _recTitle.textColor = UIColor.labelColor;
        _recTitle.numberOfLines = 1;
        [_recCard addSubview:_recTitle];
        _recPreview = [UILabel new];
        _recPreview.translatesAutoresizingMaskIntoConstraints = NO;
        _recPreview.font = [UIFont systemFontOfSize:12];
        _recPreview.textColor = UIColor.secondaryLabelColor;
        _recPreview.numberOfLines = 2;
        [_recCard addSubview:_recPreview];
        UIView *recSep = [UIView new];
        recSep.translatesAutoresizingMaskIntoConstraints = NO;
        recSep.backgroundColor = UIColor.separatorColor;
        [_recCard addSubview:recSep];
        UILabel *recFoot = [UILabel new];
        recFoot.translatesAutoresizingMaskIntoConstraints = NO;
        recFoot.font = [UIFont systemFontOfSize:11];
        recFoot.textColor = UIColor.secondaryLabelColor;
        recFoot.text = @"聊天记录 ›";
        [_recCard addSubview:recFoot];
        [NSLayoutConstraint activateConstraints:@[
            [_recCard.widthAnchor constraintEqualToConstant:240],
            [_recTitle.topAnchor constraintEqualToAnchor:_recCard.topAnchor constant:10],
            [_recTitle.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [_recTitle.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [_recPreview.topAnchor constraintEqualToAnchor:_recTitle.bottomAnchor constant:6],
            [_recPreview.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [_recPreview.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [recSep.topAnchor constraintEqualToAnchor:_recPreview.bottomAnchor constant:8],
            [recSep.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [recSep.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [recSep.heightAnchor constraintEqualToConstant:0.5],
            [recFoot.topAnchor constraintEqualToAnchor:recSep.bottomAnchor constant:6],
            [recFoot.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [recFoot.bottomAnchor constraintEqualToAnchor:_recCard.bottomAnchor constant:-8],
        ]];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _text, _thumb, _caption, _recCard]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentLeading;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        ]];
    }
    return self;
}
- (void)configureWithName:(NSString *)name type:(NSString *)type content:(NSString *)content fullURL:(NSString *)fullURL
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize caption:(NSString *)caption {
    _name.text = name;
    BOOL isRecord = [type isEqualToString:@"chat_record"];
    BOOL isImage = [type isEqualToString:@"image"];
    BOOL isVideo = [type isEqualToString:@"video"];
    BOOL isMedia = isImage || isVideo;
    // 图说条目「有字显字」：媒体/文件下方随附文本（在各分支 early-return 之前统一设置）。
    BOOL hasCaption = caption.length > 0 && (isMedia || [type isEqualToString:@"file"]);
    _caption.text = hasCaption ? caption : nil;
    _caption.hidden = !hasCaption;
    _recCard.hidden = !isRecord;
    _text.hidden = isMedia || isRecord;
    _thumb.hidden = !isMedia;
    _playBadge.hidden = !isVideo;
    if (isRecord) {
        // 套娃 mini 卡片：content 即子记录 JSON（打包时嵌套保留），标题 + 前 2 行预览。
        NSString *subTitle = nil; NSArray<NSString *> *subLines = nil;
        IMSummarizeRecord(content, &subTitle, &subLines, 2);
        _recTitle.text = subTitle;
        _recPreview.text = [subLines componentsJoinedByString:@"\n"];
        _thumb.image = nil; _thumbURL = nil;
        return;
    }
    if (!isMedia) {
        if ([type isEqualToString:@"file"]) {
            // 文件行=类型图标 + 原名 + 大小（与聊天文件气泡同语言），点击整行打开（详情页 didSelectRow）。
            NSString *fn = fileName.length > 0 ? fileName : IMMediaFileName(content);
            if (fn.length == 0) {
                _text.text = @"[文件]";
            } else {
                NSTextAttachment *att = [NSTextAttachment new];
                att.image = IMFileTypeIconForName(fn, 24);
                att.bounds = CGRectMake(0, -6, 24, 24);
                NSMutableAttributedString *line = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
                [line appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[@" " stringByAppendingString:fn]
                        attributes:@{ NSFontAttributeName: _text.font, NSForegroundColorAttributeName: self.tintColor }]];
                NSString *size = fileSize > 0 ? IMFormatFileSize(fileSize) : @"";
                if (size.length > 0) {
                    [line appendAttributedString:[[NSAttributedString alloc]
                        initWithString:[NSString stringWithFormat:@" · %@", size]
                            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13],
                                          NSForegroundColorAttributeName: UIColor.secondaryLabelColor }]];
                }
                _text.attributedText = line;
            }
        } else {
            _text.text = content;
        }
        _thumb.image = nil;
        _thumbURL = nil;
        return;
    }
    _thumb.image = nil;
    _thumbURL = fullURL;
    __weak typeof(self) ws = self;
    NSString *want = fullURL;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (self && [self->_thumbURL isEqualToString:want]) { self->_thumb.image = img; }
    };
    if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:fullURL completion:apply]; }
}
// CALayer 的 CGColor 不随明暗动态解析：外观切换时手动重刷 mini 卡片描边色（背景是动态 UIColor 会自更新）。
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        _recCard.layer.borderColor = UIColor.separatorColor.CGColor;
    }
}
@end

#pragma mark - 详情页

@interface IMChatRecordViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMChatRecordViewController {
    NSString *_host;
    NSString *_title;
    NSArray<NSDictionary *> *_items;
    UITableView *_tableView;
}

- (instancetype)initWithHost:(NSString *)host recordJSON:(NSString *)recordJSON {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _title = @"聊天记录";
        _items = @[];
        NSData *d = [recordJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if ([dict isKindOfClass:NSDictionary.class]) {
            if ([dict[@"t"] isKindOfClass:NSString.class]) { _title = dict[@"t"]; }
            if ([dict[@"items"] isKindOfClass:NSArray.class]) { _items = dict[@"items"]; }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _title;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    [_tableView registerClass:IMRecordItemCell.class forCellReuseIdentifier:@"item"];
    [self.view addSubview:_tableView];
}

- (NSString *)fullURLFor:(NSString *)content {
    if (content.length == 0) { return @""; }
    if ([content hasPrefix:@"http"] || [content hasPrefix:@"data:"]) { return content; }
    return [NSString stringWithFormat:@"http://%@%@", _host ?: @"", content];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMRecordItemCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item" forIndexPath:ip];
    NSDictionary *it = _items[ip.row];
    NSString *n = [it[@"n"] isKindOfClass:NSString.class] ? it[@"n"] : @"";
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
    NSString *fn = [it[@"fn"] isKindOfClass:NSString.class] ? it[@"fn"] : @"";
    int64_t fs = [it[@"fs"] respondsToSelector:@selector(longLongValue)] ? [it[@"fs"] longLongValue] : 0;
    NSString *cap = [it[@"cap"] isKindOfClass:NSString.class] ? it[@"cap"] : nil;
    [cell configureWithName:n type:ct content:c fullURL:[self fullURLFor:c] fileName:fn fileSize:fs caption:cap];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:NO];
    NSDictionary *it = _items[ip.row];
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
    if ([ct isEqualToString:@"chat_record"]) {
        // 套娃下钻：再 push 一层详情页渲染子记录（任意深度，靠导航栈返回）。
        // 空/非记录 JSON 不下钻（否则推出一张空白「聊天记录」死页），与顶层 openChatRecord 守卫一致。
        if (c.length == 0 || !IMLooksLikeChatRecordJSON(c)) { return; }
        IMChatRecordViewController *sub = [[IMChatRecordViewController alloc] initWithHost:_host recordJSON:c];
        [self.navigationController pushViewController:sub animated:YES];
        return;
    }
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isImage = [ct isEqualToString:@"image"];
    if (!isVideo && !isImage) {
        // 文件行：应用内浏览器打开/下载（与聊天页 openLink 同口径，仅接受 http/https）。
        if ([ct isEqualToString:@"file"]) {
            NSURL *url = [NSURL URLWithString:[self fullURLFor:c]];
            if (url && ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) {
                [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
            }
        }
        return;
    }
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:[self fullURLFor:c]
                                                                            isVideo:isVideo
                                                                     preloadedImage:nil
                                                                      onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}

@end
