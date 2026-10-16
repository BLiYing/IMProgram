//  IMQRCardView.m

#import "IMQRCardView.h"
#import "IMLocalization.h"

#import "IMQRImage.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

/// 码区边长（点）。小于 ~180 时 33×33 模块的群码在弱光下开始难扫。
static const CGFloat kIMQRCodeSide = 240;
/// 头像边长，对齐 Android `qrCardAvatar`（56dp）。
static const CGFloat kIMQRAvatarSide = 56;

@interface IMQRCardView ()
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *codeWell;        ///< 恒白底的码区（深色模式也白）
@property (nonatomic, strong) UIImageView *codeView;
@property (nonatomic, strong) UILabel *codePlaceholder; ///< 无码时的占位文案
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIView *linkBox;          ///< 链接模式：圆角灰底的链接框（替代码区）
@property (nonatomic, strong) UILabel *linkLabel;
@property (nonatomic, strong) NSLayoutConstraint *wellHintTop;
@property (nonatomic, strong) NSLayoutConstraint *linkHintTop;
@property (nonatomic, strong, readwrite, nullable) UIImage *qrImage;
@property (nonatomic, copy, nullable) NSString *renderedString; ///< 已渲染的内容串，避免重复布局时反复生成
@end

@implementation IMQRCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { [self setupUI]; }
    return self;
}

- (void)setupUI {
    self.backgroundColor = IMTheme.cardBackground;
    self.layer.cornerRadius = 20;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _avatarLabel = [UILabel new];
    _avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarLabel.textAlignment = NSTextAlignmentCenter;
    _avatarLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    _avatarLabel.textColor = UIColor.whiteColor;
    _avatarLabel.layer.cornerRadius = kIMQRAvatarSide / 2;
    _avatarLabel.clipsToBounds = YES;

    _nameLabel = [UILabel new];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    _nameLabel.textColor = IMTheme.textPrimary;
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.numberOfLines = 2;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = IMTheme.textSecondary;
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;

    _codeWell = [UIView new];
    _codeWell.translatesAutoresizingMaskIntoConstraints = NO;
    _codeWell.backgroundColor = UIColor.whiteColor; // 固定白，勿用语义色
    _codeWell.layer.cornerRadius = 12;
    _codeWell.layer.cornerCurve = kCACornerCurveContinuous;

    _codeView = [UIImageView new];
    _codeView.translatesAutoresizingMaskIntoConstraints = NO;
    _codeView.contentMode = UIViewContentModeScaleAspectFit;

    _codePlaceholder = [UILabel new];
    _codePlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    _codePlaceholder.textAlignment = NSTextAlignmentCenter;
    _codePlaceholder.font = [UIFont systemFontOfSize:13];
    _codePlaceholder.textColor = UIColor.systemGrayColor; // 白底上，故不用语义次要色
    _codePlaceholder.text = IMLocalized(@"qr.card.loading");

    _linkBox = [UIView new];
    _linkBox.translatesAutoresizingMaskIntoConstraints = NO;
    _linkBox.backgroundColor = IMTheme.groupedBackground;
    _linkBox.layer.cornerRadius = 12;
    _linkBox.layer.cornerCurve = kCACornerCurveContinuous;
    _linkBox.hidden = YES;

    _linkLabel = [UILabel new];
    _linkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _linkLabel.numberOfLines = 3;
    _linkLabel.lineBreakMode = NSLineBreakByCharWrapping;
    _linkLabel.textAlignment = NSTextAlignmentCenter;
    _linkLabel.font = [UIFont systemFontOfSize:14];
    _linkLabel.textColor = IMTheme.textPrimary;
    [_linkBox addSubview:_linkLabel];

    _hintLabel = [UILabel new];
    _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _hintLabel.numberOfLines = 0;
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.font = [UIFont systemFontOfSize:12];
    _hintLabel.textColor = IMTheme.textSecondary;

    [self addSubview:_avatarLabel];
    [self addSubview:_nameLabel];
    [self addSubview:_subtitleLabel];
    [self addSubview:_codeWell];
    [self addSubview:_linkBox];
    [_codeWell addSubview:_codePlaceholder];
    [_codeWell addSubview:_codeView];
    [self addSubview:_hintLabel];

    CGFloat pad = IMTheme.space4;
    // 头像 / 名字 / 副标题竖排居中（对齐 Android `QrCardScreen`）；码区与链接框共用同一锚点位置。
    NSLayoutConstraint *linkTop = [_linkBox.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:20];
    NSLayoutConstraint *wellTop = [_codeWell.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:20];
    _linkHintTop = [_hintLabel.topAnchor constraintEqualToAnchor:_linkBox.bottomAnchor constant:IMTheme.space3];
    _linkHintTop.active = NO;
    _wellHintTop = [_hintLabel.topAnchor constraintEqualToAnchor:_codeWell.bottomAnchor constant:IMTheme.space3];
    [NSLayoutConstraint activateConstraints:@[
        [_avatarLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_avatarLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],
        [_avatarLabel.widthAnchor constraintEqualToConstant:kIMQRAvatarSide],
        [_avatarLabel.heightAnchor constraintEqualToConstant:kIMQRAvatarSide],

        [_nameLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:pad],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-pad],
        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarLabel.bottomAnchor constant:10],

        [_subtitleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_subtitleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:pad],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-pad],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],

        [_codeWell.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        wellTop,
        [_codeWell.widthAnchor constraintEqualToConstant:kIMQRCodeSide + 16],
        [_codeWell.heightAnchor constraintEqualToConstant:kIMQRCodeSide + 16],

        [_linkBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
        [_linkBox.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-pad],
        linkTop,
        [_linkLabel.topAnchor constraintEqualToAnchor:_linkBox.topAnchor constant:14],
        [_linkLabel.bottomAnchor constraintEqualToAnchor:_linkBox.bottomAnchor constant:-14],
        [_linkLabel.leadingAnchor constraintEqualToAnchor:_linkBox.leadingAnchor constant:12],
        [_linkLabel.trailingAnchor constraintEqualToAnchor:_linkBox.trailingAnchor constant:-12],

        [_codeView.centerXAnchor constraintEqualToAnchor:_codeWell.centerXAnchor],
        [_codeView.centerYAnchor constraintEqualToAnchor:_codeWell.centerYAnchor],
        [_codeView.widthAnchor constraintEqualToConstant:kIMQRCodeSide],
        [_codeView.heightAnchor constraintEqualToConstant:kIMQRCodeSide],

        [_codePlaceholder.centerXAnchor constraintEqualToAnchor:_codeWell.centerXAnchor],
        [_codePlaceholder.centerYAnchor constraintEqualToAnchor:_codeWell.centerYAnchor],
        [_codePlaceholder.leadingAnchor constraintEqualToAnchor:_codeWell.leadingAnchor constant:8],
        [_codePlaceholder.trailingAnchor constraintEqualToAnchor:_codeWell.trailingAnchor constant:-8],

        [_hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
        [_hintLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-pad],
        _wellHintTop,
        [_hintLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-24],
    ]];
}

- (void)configureWithAvatarURL:(NSString *)avatarURL
                          seed:(NSString *)seed
                          name:(NSString *)name
                      subtitle:(NSString *)subtitle
                      qrString:(NSString *)qrString
                          hint:(NSString *)hint {
    [self.avatarLabel im_setAvatarURL:avatarURL seed:seed ?: @"" displayName:name];
    self.nameLabel.text = name;
    self.subtitleLabel.text = subtitle ?: @"";
    self.hintLabel.text = hint ?: @"";

    if (self.linkMode) {
        // 链接模式：不画码，链接本身是主角（可长按选中复制由宿主的「复制链接」按钮负责）。
        self.codeWell.hidden = YES;
        self.linkBox.hidden = NO;
        self.wellHintTop.active = NO;
        self.linkHintTop.active = YES;
        self.linkLabel.text = qrString.length ? qrString : IMLocalized(@"qr.card.loading");
        self.linkLabel.textColor = qrString.length ? IMTheme.textPrimary : IMTheme.textSecondary;
        return;
    }

    if (qrString.length == 0) {
        self.renderedString = nil;
        self.qrImage = nil;
        self.codeView.image = nil;
        self.codeView.hidden = YES;
        self.codePlaceholder.hidden = NO;
        return;
    }
    if (![qrString isEqualToString:self.renderedString]) {
        self.renderedString = qrString;
        self.qrImage = [IMQRImage imageForString:qrString size:kIMQRCodeSide];
    }
    self.codeView.image = self.qrImage;
    self.codeView.hidden = (self.qrImage == nil);
    self.codePlaceholder.hidden = (self.qrImage != nil);
    self.codePlaceholder.text = self.qrImage ? @"" : IMLocalized(@"qr.card.gen_failed");
}

@end
