//  IMFavoritesViewController.m

#import "IMFavoritesViewController.h"
#import "IMHTTPService.h"
#import "IMMediaUtil.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaViewerViewController.h"
#import "IMTheme.h"

#pragma mark - 收藏 Cell（文本/链接直显；图片/视频缩略图；文件名）

@interface IMFavoriteCell : UITableViewCell
- (void)configureWithContentType:(NSString *)ct fullURL:(NSString *)fullURL text:(NSString *)text;
@end

@implementation IMFavoriteCell {
    UIImageView *_thumb;
    UIImageView *_playBadge;
    UILabel *_text;
    NSString *_thumbURL;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 6;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        [self.contentView addSubview:_thumb];
        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = UIColor.whiteColor;
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [self.contentView addSubview:_playBadge];
        _text = [UILabel new];
        _text.translatesAutoresizingMaskIntoConstraints = NO;
        _text.numberOfLines = 3;
        _text.font = [UIFont systemFontOfSize:15];
        [self.contentView addSubview:_text];
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_thumb.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_thumb.widthAnchor constraintEqualToConstant:56],
            [_thumb.heightAnchor constraintEqualToConstant:56],
            [_thumb.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
            [_thumb.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_text.leadingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:10],
            [_text.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_text.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_text.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}
- (void)configureWithContentType:(NSString *)ct fullURL:(NSString *)fullURL text:(NSString *)text {
    BOOL isImage = [ct isEqualToString:@"image"];
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isMedia = isImage || isVideo;
    _thumb.hidden = !isMedia;
    _playBadge.hidden = !isVideo;
    _thumb.image = nil;
    if ([ct isEqualToString:@"file"]) {
        // 文件：复用文件选择/聊天/详情同一套原色折角图标。
        NSString *fname = IMMediaFileName(text);
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = IMFileTypeIconForName(fname, 22);
        att.bounds = CGRectMake(0, -5, 22, 22);
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithAttributedString:
            [NSAttributedString attributedStringWithAttachment:att]];
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:fname]
            attributes:@{ NSFontAttributeName: _text.font, NSForegroundColorAttributeName: IMTheme.accent }]];
        _text.attributedText = s;
    } else {
        _text.text = text;
    }
    if (!isMedia) { _thumbURL = nil; return; }
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

// ⚠️ 必须是普通 UIViewController + 内嵌 UITableView（而非 UITableViewController）：
// 导航容器 IMMainNavigationController 会给 push 进来的页面注入 IMLiquidNavigationBar 到 vc.view 上，
// 并 additionalSafeAreaInsets.top=56。UITableViewController 的 vc.view 本身就是滚动的 tableView，
// 注入栏被约束到滚动视图 topAnchor 会被初始负 contentOffset 推到内容坐标之下 → 标题栏整体下移
// （且随滚动漂移）。改为普通 VC，栏挂在静止的 self.view 上，位置才正确（对齐外观页/设置页写法）。
@interface IMFavoritesViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMFavoritesViewController {
    UITableView *_tableView;
    NSArray<NSDictionary *> *_items; // 每项含 id/content/content_type/...
}

- (instancetype)init {
    self = [super init];
    if (self) { self.title = @"收藏消息"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _items = @[];
    self.view.backgroundColor = IMTheme.groupedBackground;
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.rowHeight = 76;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:IMFavoriteCell.class forCellReuseIdentifier:@"fav"];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [self reload];
}

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService favoritesWithToken:token completion:^(NSArray<NSDictionary *> *favorites, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_items = error ? @[] : (favorites ?: @[]);
        [self->_tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMFavoriteCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fav" forIndexPath:indexPath];
    NSDictionary *f = _items[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:[NSString class]] ? f[@"content"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:[NSString class]] ? f[@"content_type"] : @"text";
    [cell configureWithContentType:ct fullURL:IMMediaFullURL(content, IMHTTPService.sharedService.host) text:content];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

/// 点击收藏项：图片/视频 → 全屏查看器（复用）；链接 → 略（v1 不在收藏页打开）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSDictionary *f = _items[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:[NSString class]] ? f[@"content"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:[NSString class]] ? f[@"content_type"] : @"text";
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isImage = [ct isEqualToString:@"image"];
    if (!isVideo && !isImage) { return; }
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:IMMediaFullURL(content, IMHTTPService.sharedService.host)
                                                                            isVideo:isVideo preloadedImage:nil onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"删除" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [ws deleteAt:indexPath done:completionHandler];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)deleteAt:(NSIndexPath *)indexPath done:(void (^)(BOOL))done {
    if (indexPath.row >= (NSInteger)_items.count) { done(NO); return; }
    NSDictionary *f = _items[(NSUInteger)indexPath.row];
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (fid <= 0 || token.length == 0) { done(NO); return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteFavoriteWithToken:token favoriteID:fid completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { done(NO); return; }
        if (error) { done(NO); return; }
        NSMutableArray *m = [self->_items mutableCopy];
        if (indexPath.row < (NSInteger)m.count) { [m removeObjectAtIndex:(NSUInteger)indexPath.row]; }
        self->_items = m;
        [self->_tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        done(YES);
    }];
}

@end
