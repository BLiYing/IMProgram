#import "IMAlbumCell.h"
#import "IMMessageModel.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

@interface IMAlbumTileView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *playBadge;
@property (nonatomic, strong) IMMessageModel *member; ///< 本格对应的消息（tap/菜单定位用）
@property (nonatomic, copy)   NSString *loadKey;      ///< 异步加载防串图
- (void)setProgress:(nullable NSNumber *)p; ///< nil=无/完成；0..1=环形进度；<0=失败
@end

@implementation IMAlbumTileView {
    UIView       *_dim;      // 上传中压暗
    CAShapeLayer *_ringBG;   // 环底
    CAShapeLayer *_ring;     // 进度环
    UILabel      *_failBadge;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.backgroundColor = UIColor.tertiarySystemFillColor;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];

        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _dim.hidden = YES;
        [self addSubview:_dim];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.hidden = YES;
        [self addSubview:_playBadge];

        UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:CGPointMake(18, 18) radius:15
                                                          startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        _ringBG = [CAShapeLayer layer];
        _ringBG.path = circle.CGPath;
        _ringBG.fillColor = UIColor.clearColor.CGColor;
        _ringBG.strokeColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        _ringBG.lineWidth = 3;
        _ringBG.frame = CGRectMake(0, 0, 36, 36);
        _ringBG.hidden = YES;
        [self.layer addSublayer:_ringBG];

        _ring = [CAShapeLayer layer];
        _ring.path = circle.CGPath;
        _ring.fillColor = UIColor.clearColor.CGColor;
        _ring.strokeColor = UIColor.whiteColor.CGColor;
        _ring.lineWidth = 3;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0;
        _ring.frame = CGRectMake(0, 0, 36, 36);
        _ring.hidden = YES;
        [self.layer addSublayer:_ring];

        _failBadge = [UILabel new];
        _failBadge.text = @"!";
        _failBadge.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 14;
        _failBadge.clipsToBounds = YES;
        _failBadge.hidden = YES;
        [self addSubview:_failBadge];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGPoint c = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    _playBadge.center = c;
    _failBadge.frame = CGRectMake(0, 0, 28, 28);
    _failBadge.center = c;
    CGRect ringFrame = CGRectMake(c.x - 18, c.y - 18, 36, 36);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ringBG.frame = ringFrame;
    _ring.frame = ringFrame;
    [CATransaction commit];
}
- (void)setProgress:(NSNumber *)p {
    if (!p || p.floatValue >= 1) { // 无进度 / 完成
        _dim.hidden = YES; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = YES;
        return;
    }
    if (p.floatValue < 0) { // 失败
        _dim.hidden = NO; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = NO;
        return;
    }
    _dim.hidden = NO; _failBadge.hidden = YES;
    _ringBG.hidden = NO; _ring.hidden = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES]; // 高频进度回调不做隐式动画（避免滞后）
    _ring.strokeEnd = MAX(0.02, p.floatValue); // 0% 也露一点头，可感知"在动"
    [CATransaction commit];
}
@end

/// 相册宫格 cell：leader 行渲染同组全部成员；行高由块布局决定（同数量恒定高，进度/缩略图更新不动布局）。
static NSArray<NSNumber *> *IMAlbumRowPattern(NSUInteger n) {
    switch (n) {
        case 1:  return @[@1];
        case 2:  return @[@2];
        case 3:  return @[@1, @2];
        case 4:  return @[@2, @2];
        case 5:  return @[@2, @3];
        case 6:  return @[@3, @3];
        case 7:  return @[@1, @3, @3];
        case 8:  return @[@2, @3, @3];
        default: return @[@3, @3, @3]; // 9（selectionLimit=9 封顶）
    }
}

static const CGFloat kIMAlbumWidth = 240;
static const CGFloat kIMAlbumGap = 2;

/// 给定块数的宫格总高（布局确定 → 行高确定，自适应行高稳定）。
static CGFloat IMAlbumHeightForCount(NSUInteger n) {
    if (n == 0) { return 0; }
    CGFloat h = 0;
    for (NSNumber *k in IMAlbumRowPattern(n)) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileH = cols == 1 ? 150 : (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        h += tileH + kIMAlbumGap;
    }
    return h - kIMAlbumGap;
}

@interface IMAlbumCell () <UIContextMenuInteractionDelegate>
@end

@implementation IMAlbumCell {
    UIView *_container;                        // 固定宽 240，圆角裁切
    NSMutableArray<IMAlbumTileView *> *_tiles; // 复用池（按需增建）
    UILabel *_metaChip;                        // 右下角 时间+状态 小胶囊
    UILabel *_senderLabel;                     // 群聊对方昵称（宫格上方）
    UILabel *_avatar;                          // 群聊对方头像（连续段末条，贴宫格底左侧）
    NSLayoutConstraint *_containerHeight;
    NSLayoutConstraint *_leading, *_trailing;
    NSLayoutConstraint *_containerTopPlain;      // 无昵称：宫格贴 cell 顶
    NSLayoutConstraint *_containerTopUnderName;  // 有昵称：宫格挂昵称下方
    NSString *_host;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _tiles = [NSMutableArray array];
        _container = [UIView new];
        _container.translatesAutoresizingMaskIntoConstraints = NO;
        _container.layer.cornerRadius = IMTheme.radiusBubble;
        _container.clipsToBounds = YES;
        [self.contentView addSubview:_container];

        _metaChip = [UILabel new];
        _metaChip.font = [UIFont systemFontOfSize:11];
        _metaChip.textColor = UIColor.whiteColor;
        _metaChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _metaChip.layer.cornerRadius = 9;
        _metaChip.clipsToBounds = YES;
        _metaChip.textAlignment = NSTextAlignmentCenter;
        [_container addSubview:_metaChip];

        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        [self.contentView addSubview:_avatar];

        _leading = [_container.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_container.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _containerHeight = [_container.heightAnchor constraintEqualToConstant:100];
        _containerTopPlain = [_container.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _containerTopUnderName = [_container.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _containerTopPlain.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_container.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_container.widthAnchor constraintEqualToConstant:kIMAlbumWidth],
            _containerHeight,
        ]];
    }
    return self;
}

- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, NSNumber *> *)progress
                  senderName:(NSString *)senderName {
    _container.layer.cornerRadius = IMTheme.radiusBubble;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _host = host;
    _leading.active = !mine;
    _trailing.active = mine;
    BOOL showName = senderName.length > 0;
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    _containerTopPlain.active = !showName;
    _containerTopUnderName.active = showName;
    _containerHeight.constant = IMAlbumHeightForCount(members.count);

    // 按需补足块视图；多余的隐藏。
    while (_tiles.count < members.count) {
        IMAlbumTileView *tile = [[IMAlbumTileView alloc] initWithFrame:CGRectZero];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tileTapped:)];
        [tile addGestureRecognizer:tap];
        [tile addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
        [_container addSubview:tile];
        [_tiles addObject:tile];
    }
    for (NSUInteger i = members.count; i < _tiles.count; i++) { _tiles[i].hidden = YES; }

    // 布局块（frame 手排，宽 240 固定；行模式决定块尺寸）。
    NSArray<NSNumber *> *pattern = IMAlbumRowPattern(members.count);
    NSUInteger idx = 0;
    CGFloat y = 0;
    for (NSNumber *k in pattern) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileW = (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        CGFloat tileH = cols == 1 ? 150 : tileW;
        for (NSUInteger c = 0; c < cols && idx < members.count; c++, idx++) {
            IMAlbumTileView *tile = _tiles[idx];
            tile.hidden = NO;
            tile.frame = CGRectMake(c * (tileW + kIMAlbumGap), y, cols == 1 ? kIMAlbumWidth : tileW, tileH);
            [self bindTile:tile toMember:members[idx] previews:previews progress:progress];
        }
        y += tileH + kIMAlbumGap;
    }
    [_container bringSubviewToFront:_metaChip];
    [self updateMetaWithMembers:members mine:mine];
}

/// 单块绑定：本地预览优先（上传中/防闪），否则按 URL 异步加载（复用防串图）。
- (void)bindTile:(IMAlbumTileView *)tile toMember:(IMMessageModel *)m
        previews:(NSDictionary<NSString *, UIImage *> *)previews
        progress:(NSDictionary<NSString *, NSNumber *> *)progress {
    tile.member = m;
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    tile.playBadge.hidden = !isVideo;
    [tile setProgress:progress[m.clientMsgID ?: @""]];

    UIImage *preview = previews[m.clientMsgID ?: @""];
    if (preview) { tile.imageView.image = preview; tile.loadKey = nil; return; }
    if (m.content.length == 0) { tile.imageView.image = nil; tile.loadKey = nil; return; } // 占位灰底
    NSString *full = IMMediaFullURL(m.content, _host);
    tile.loadKey = full;
    tile.imageView.image = nil;
    __weak IMAlbumTileView *wt = tile;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong IMAlbumTileView *t = wt;
        if (t && img && [t.loadKey isEqualToString:full]) { t.imageView.image = img; }
    };
    if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:full completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:full completion:apply]; }
}

- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, NSNumber *> *)progress {
    BOOL mine = NO;
    NSMutableArray<IMMessageModel *> *members = [NSMutableArray array];
    for (IMAlbumTileView *tile in _tiles) {
        IMMessageModel *m = tile.member;
        if (tile.hidden || !m) { continue; }
        [members addObject:m];
        mine = mine || m.status != IMMessageStatusReceived;
        [tile setProgress:progress[m.clientMsgID ?: @""]];
        UIImage *preview = previews[m.clientMsgID ?: @""];
        if (preview && tile.imageView.image == nil) { tile.imageView.image = preview; }
    }
    [self updateMetaWithMembers:members mine:mine];
}

/// 右下角小胶囊：末条成员时间 + 自己消息的状态（… 发送中 / ✓ 全部送达 / ! 有失败）。
- (void)updateMetaWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine {
    IMMessageModel *last = members.lastObject;
    if (!last) { _metaChip.hidden = YES; return; }
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm";
    NSString *time = last.timestamp > 0
        ? [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:last.timestamp / 1000.0]] : @"";
    NSString *suffix = @"";
    if (mine) {
        BOOL anyFailed = NO, allSent = YES;
        for (IMMessageModel *m in members) {
            if (m.status == IMMessageStatusFailed) { anyFailed = YES; }
            if (m.status != IMMessageStatusSent) { allSent = NO; }
        }
        suffix = anyFailed ? @" !" : (allSent ? @" ✓" : @" …");
    }
    _metaChip.hidden = NO;
    _metaChip.text = [NSString stringWithFormat:@" %@%@ ", time, suffix];
    [_metaChip sizeToFit];
    CGSize s = CGSizeMake(_metaChip.bounds.size.width + 8, 18);
    _metaChip.frame = CGRectMake(kIMAlbumWidth - s.width - 6, _containerHeight.constant - s.height - 6, s.width, s.height);
}

- (void)tileTapped:(UITapGestureRecognizer *)gr {
    IMAlbumTileView *tile = (IMAlbumTileView *)gr.view;
    if ([tile isKindOfClass:IMAlbumTileView.class] && tile.member && _onTapItem) { _onTapItem(tile.member); }
}

/// 每块自带长按菜单（定位到该块对应的单条消息 → 单张引用/转发/撤回/收藏等）。
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    IMAlbumTileView *tile = (IMAlbumTileView *)interaction.view;
    if (![tile isKindOfClass:IMAlbumTileView.class] || !tile.member || !_menuForItem) { return nil; }
    IMMessageModel *m = tile.member;
    UIMenu * (^provider)(IMMessageModel *) = _menuForItem;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) { return provider(m); }];
}

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _leading.constant = gutter ? 48 : 12;   // 对方群消息留 30 头像列（12 + 30 + 6）
    if (gutter && showAvatar) {
        _avatar.hidden = NO;
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    } else {
        _avatar.hidden = YES;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (IMAlbumTileView *tile in _tiles) { tile.member = nil; tile.loadKey = nil; tile.imageView.image = nil; [tile setProgress:nil]; }
    _avatar.hidden = YES;
    _leading.constant = 12;
    _onTapItem = nil;
    _menuForItem = nil;
}
@end
