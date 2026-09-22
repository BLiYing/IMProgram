//  IMGroupAvatarHeader.m
//  见头文件。视图搭建逐字来自 IMGroupManageViewController.m（2026-09-05 提取），只加了 initial 一层。

#import "IMGroupAvatarHeader.h"
#import "IMLocalization.h"
#import "IMTheme.h"

@implementation IMGroupAvatarHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _avatar = [UIImageView new];
        _avatar.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.18];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES; _avatar.layer.cornerRadius = 45;
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_avatar];
        UIImageSymbolConfiguration *camCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
        _cam = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"camera.fill"] imageByApplyingSymbolConfiguration:camCfg]];
        UIImageView *cam = _cam;
        cam.tintColor = IMTheme.accent; cam.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatar addSubview:cam];
        _initial = [UILabel new];
        _initial.font = [UIFont systemFontOfSize:30 weight:UIFontWeightSemibold];
        _initial.textColor = IMTheme.accent;
        _initial.textAlignment = NSTextAlignmentCenter;
        _initial.hidden = YES;                       // 默认不显示：群管理页只要相机圈
        _initial.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatar addSubview:_initial];
        _caption = [UILabel new];
        _caption.text = IMLocalized(@"group.avatar.set_new"); _caption.textColor = IMTheme.accent;
        _caption.font = [UIFont systemFontOfSize:15]; _caption.textAlignment = NSTextAlignmentCenter;
        _caption.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_caption];
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_avatar.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
            [_avatar.widthAnchor constraintEqualToConstant:90], [_avatar.heightAnchor constraintEqualToConstant:90],
            [cam.centerXAnchor constraintEqualToAnchor:_avatar.centerXAnchor],
            [cam.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            [_initial.centerXAnchor constraintEqualToAnchor:_avatar.centerXAnchor],
            [_initial.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            [_caption.topAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:8],
            [_caption.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (void)applyAvatarImage:(UIImage *)image placeholder:(NSString *)placeholder caption:(NSString *)caption {
    self.avatar.image = image;
    NSString *ph = image ? @"" : (placeholder ?: @"");
    self.initial.text = ph;
    self.initial.hidden = ph.length == 0;
    self.cam.hidden = image != nil || ph.length > 0;
    self.caption.text = caption ?: @"";
}

@end
