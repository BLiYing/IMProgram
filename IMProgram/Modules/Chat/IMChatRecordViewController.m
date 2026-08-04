//  IMChatRecordViewController.m

#import "IMChatRecordViewController.h"
#import <SafariServices/SafariServices.h>
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "IMMediaViewerViewController.h"

#pragma mark - 单条记录 Cell

@interface IMRecordItemCell : UITableViewCell
- (void)configureWithName:(NSString *)name type:(NSString *)type content:(NSString *)content fullURL:(NSString *)fullURL
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize;
@end

@implementation IMRecordItemCell {
    UILabel *_name;
    UILabel *_text;
    UIImageView *_thumb;
    UIImageView *_playBadge;
    NSString *_thumbURL;
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

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _text, _thumb]];
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
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize {
    _name.text = name;
    BOOL isImage = [type isEqualToString:@"image"];
    BOOL isVideo = [type isEqualToString:@"video"];
    BOOL isMedia = isImage || isVideo;
    _text.hidden = isMedia;
    _thumb.hidden = !isMedia;
    _playBadge.hidden = !isVideo;
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
    [cell configureWithName:n type:ct content:c fullURL:[self fullURLFor:c] fileName:fn fileSize:fs];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:NO];
    NSDictionary *it = _items[ip.row];
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
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
