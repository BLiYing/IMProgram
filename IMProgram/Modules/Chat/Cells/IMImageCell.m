#import "IMImageCell.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

@implementation IMImageCell {
    UIImageView *_thumb;
    UIImageView *_playBadge;   // 视频封面上的播放角标
    UIView  *_progressWrap;    // 居中进度胶囊（上传中）
    UILabel *_progressLabel;
    UILabel *_senderLabel;     // 群聊对方昵称（缩略图上方）
    UILabel *_avatar;          // 群聊对方头像（连续段末条，贴缩略图底左侧）
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_thumbTopPlain;      // 无昵称：thumb 贴 cell 顶
    NSLayoutConstraint *_thumbTopUnderName;  // 有昵称：thumb 挂昵称下方
    NSString *_url;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = IMTheme.radiusBubble;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.userInteractionEnabled = YES;
        [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_thumb];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [self.contentView addSubview:_playBadge];

        _progressWrap = [UIView new];
        _progressWrap.translatesAutoresizingMaskIntoConstraints = NO;
        _progressWrap.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _progressWrap.layer.cornerRadius = 14;
        _progressWrap.hidden = YES;
        [self.contentView addSubview:_progressWrap];
        _progressLabel = [UILabel new];
        _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _progressLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        _progressLabel.textColor = UIColor.whiteColor;
        [_progressWrap addSubview:_progressLabel];

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

        _leading = [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbTopPlain = [_thumb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _thumbTopUnderName = [_thumb.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _thumbTopPlain.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_thumb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_thumb.widthAnchor constraintEqualToConstant:180],
            [_thumb.heightAnchor constraintEqualToConstant:180],
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_progressWrap.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_progressWrap.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_progressWrap.heightAnchor constraintEqualToConstant:28],
            [_progressLabel.leadingAnchor constraintEqualToAnchor:_progressWrap.leadingAnchor constant:12],
            [_progressLabel.trailingAnchor constraintEqualToAnchor:_progressWrap.trailingAnchor constant:-12],
            [_progressLabel.centerYAnchor constraintEqualToAnchor:_progressWrap.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setUploadProgress:(float)p {
    if (p < -1.5) { // -2：失败
        _progressWrap.hidden = NO;
        _progressLabel.text = @"发送失败";
        return;
    }
    if (p < 0 || p >= 1) { _progressWrap.hidden = YES; return; } // 无进度态 / 已完成
    _progressWrap.hidden = NO;
    [self.contentView bringSubviewToFront:_progressWrap];
    _progressLabel.text = p <= 0 ? @"等待中" : [NSString stringWithFormat:@"%d%%", (int)(p * 100)];
}
- (void)configureWithURL:(NSString *)fullURL isVideo:(BOOL)isVideo mine:(BOOL)mine previewImage:(UIImage *)preview senderName:(NSString *)senderName {
    _thumb.layer.cornerRadius = IMTheme.radiusBubble;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _url = fullURL;
    _leading.active = !mine;
    _trailing.active = mine;
    BOOL showName = senderName.length > 0;
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    _thumbTopPlain.active = !showName;
    _thumbTopUnderName.active = showName;
    _thumb.image = preview; // 本地预览先行（上传中/防闪）；无预览为 nil 占位灰底
    _playBadge.hidden = !isVideo;
    _progressWrap.hidden = YES;
    if (fullURL.length == 0) { return; } // 尚未上传完成：只显本地预览，不发起网络加载
    __weak typeof(self) ws = self;
    NSString *want = fullURL;
    void (^apply)(UIImage *) = ^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (self && image && [self->_url isEqualToString:want]) { self->_thumb.image = image; } // 复用安全
    };
    if (isVideo) {
        [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:apply]; // 视频显首帧
    } else {
        [[IMImageLoader shared] loadImageURL:fullURL completion:apply];
    }
}
- (void)tapped { if (_onTap) { _onTap(_thumb.image); } }
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
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; _playBadge.hidden = YES; _progressWrap.hidden = YES;
    _senderLabel.hidden = YES; _senderLabel.text = nil; _thumbTopUnderName.active = NO; _thumbTopPlain.active = YES;
    _avatar.hidden = YES; _leading.constant = 12; _onTap = nil; }
@end
