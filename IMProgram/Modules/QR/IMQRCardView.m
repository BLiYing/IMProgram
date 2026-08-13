//  IMQRCardView.m

#import "IMQRCardView.h"

#import "IMQRImage.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

/// 码区边长（点）。小于 ~180 时 33×33 模块的群码在弱光下开始难扫。
static const CGFloat kIMQRCodeSide = 200;

@interface IMQRCardView ()
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *codeWell;        ///< 恒白底的码区（深色模式也白）
@property (nonatomic, strong) UIImageView *codeView;
@property (nonatomic, strong) UILabel *codePlaceholder; ///< 无码时的占位文案
@property (nonatomic, strong) UILabel *hintLabel;
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
    _avatarLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _avatarLabel.textColor = UIColor.whiteColor;
    _avatarLabel.layer.cornerRadius = 24;
    _avatarLabel.clipsToBounds = YES;

    _nameLabel = [UILabel new];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _nameLabel.textColor = IMTheme.textPrimary;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = IMTheme.textSecondary;

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
    _codePlaceholder.text = @"二维码加载中…";

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
    [_codeWell addSubview:_codePlaceholder];
    [_codeWell addSubview:_codeView];
    [self addSubview:_hintLabel];

    CGFloat pad = IMTheme.space4;
    [NSLayoutConstraint activateConstraints:@[
        [_avatarLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
        [_avatarLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:pad],
        [_avatarLabel.widthAnchor constraintEqualToConstant:48],
        [_avatarLabel.heightAnchor constraintEqualToConstant:48],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarLabel.trailingAnchor constant:IMTheme.space3],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-pad],
        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarLabel.topAnchor constant:4],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-pad],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],

        [_codeWell.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_codeWell.topAnchor constraintEqualToAnchor:_avatarLabel.bottomAnchor constant:pad],
        [_codeWell.widthAnchor constraintEqualToConstant:kIMQRCodeSide + 16],
        [_codeWell.heightAnchor constraintEqualToConstant:kIMQRCodeSide + 16],

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
        [_hintLabel.topAnchor constraintEqualToAnchor:_codeWell.bottomAnchor constant:IMTheme.space3],
        [_hintLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-pad],
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
    self.codePlaceholder.text = self.qrImage ? @"" : @"二维码生成失败";
}

@end
