//  IMInAppBannerView.m

#import "IMInAppBannerView.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMInAppBannerContent.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMAppearance.h"
#import "IMPowerSaving.h" // 动画生效值 = 外观偏好 && !省电
#import "IMConversationRouter.h"
#import "IMChatPresence.h"
#import "IMRemarkStore.h"
#import "IMNotificationSettings.h"
#import "IMMediaUtil.h"

static CGFloat const kIMBannerSideMargin = 8;
static CGFloat const kIMBannerRadius = 14;
static CGFloat const kIMBannerAvatarSize = 40;
static NSTimeInterval const kIMBannerSlideDuration = 0.25;
static NSTimeInterval const kIMBannerAutoDismissDelay = 4.0;

@interface IMInAppBannerPresenter : NSObject
+ (instancetype)shared;
- (void)showForConversation:(IMConversation *)conversation message:(IMMessageModel *)message
                        host:(NSString *)host userID:(NSString *)userID;
- (void)dismissAnimated:(BOOL)animated;
@end

@implementation IMInAppBannerPresenter {
    UIView *_card;           // UIControl 承载触摸态（按住暂停计时 / 松手判定为点击）
    UILabel *_avatar;
    UILabel *_titleLabel;
    UILabel *_bodyLabel;
    NSLayoutConstraint *_topConstraint;
    CGFloat _hiddenTopConstant; // 卡片完全滑出屏幕时 top 约束的值（= -(安全区+估算高度)）

    NSTimer *_dismissTimer;
    NSTimeInterval _remainingInterval;
    CFAbsoluteTime _timerArmedAt;

    NSString *_convID;
    NSString *_host;
    NSString *_userID;
    IMConversation *_conversation;
    BOOL _visible;
}

+ (instancetype)shared {
    static IMInAppBannerPresenter *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [IMInAppBannerPresenter new];
        // 只在单例创建时注册一次（单例不释放、不需要配对移除）。放在 buildIfNeededInHost: 里的话，
        // 每次换宿主窗口都会再注册一遍，回调重复触发（/code-review 2026-09-29）。
        [NSNotificationCenter.defaultCenter addObserver:p selector:@selector(presenceChanged:)
                                                    name:IMChatPresenceDidChangeNotification object:nil];
    });
    return p;
}

#pragma mark - 构建（懒建一次，之后复用同一套视图，避免每条消息都新建/销毁窗口子视图）

- (UIView *)hostView {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) { continue; }
        if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (keyWindow) { break; }
    }
    return keyWindow;
}

- (void)buildIfNeededInHost:(UIView *)host {
    if (_card && _card.superview == host) { return; }
    [_card removeFromSuperview]; // 罕见：key window 切换（如新建场景）时重挂到新宿主

    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = IMTheme.surfaceElevated;
    card.layer.cornerRadius = kIMBannerRadius;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.16;
    card.layer.shadowRadius = 10;
    card.layer.shadowOffset = CGSizeMake(0, 3);
    [card addTarget:self action:@selector(handleTouchDown) forControlEvents:UIControlEventTouchDown];
    [card addTarget:self action:@selector(handleTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
    [card addTarget:self action:@selector(handleTouchEndedWithoutTap)
    forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeUp)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    [card addGestureRecognizer:swipe];
    [host addSubview:card];
    _card = card;

    UILabel *avatar = [UILabel new];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.textAlignment = NSTextAlignmentCenter;
    avatar.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    avatar.textColor = UIColor.whiteColor;
    avatar.layer.cornerRadius = kIMBannerAvatarSize / 2.0;
    avatar.layer.masksToBounds = YES;
    avatar.userInteractionEnabled = NO;
    [card addSubview:avatar];
    _avatar = avatar;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    title.numberOfLines = 1;
    title.userInteractionEnabled = NO;
    [card addSubview:title];
    _titleLabel = title;

    UILabel *body = [UILabel new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.font = [UIFont systemFontOfSize:14];
    body.textColor = IMTheme.textSecondary;
    body.numberOfLines = 2;
    body.userInteractionEnabled = NO;
    [card addSubview:body];
    _bodyLabel = body;

    UILayoutGuide *g = host.safeAreaLayoutGuide;
    _topConstraint = [card.topAnchor constraintEqualToAnchor:g.topAnchor constant:kIMBannerSideMargin];
    [NSLayoutConstraint activateConstraints:@[
        _topConstraint,
        [card.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:kIMBannerSideMargin],
        [card.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-kIMBannerSideMargin],

        [avatar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:IMTheme.space3],
        [avatar.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [avatar.widthAnchor constraintEqualToConstant:kIMBannerAvatarSize],
        [avatar.heightAnchor constraintEqualToConstant:kIMBannerAvatarSize],
        [avatar.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:IMTheme.space3],
        [avatar.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-IMTheme.space3],

        [title.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:IMTheme.space3],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-IMTheme.space3],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:IMTheme.space3],

        [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [body.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-IMTheme.space3],
    ]];
    card.hidden = YES;
    card.alpha = 0;
    _visible = NO; // 新卡片是隐藏的：换宿主时若旧卡正显示，不复位的话下一条会走「原地换内容」分支，永远不滑出来
}

#pragma mark - 展示/刷新

- (void)showForConversation:(IMConversation *)conversation message:(IMMessageModel *)message
                        host:(NSString *)host userID:(NSString *)userID {
    UIView *hostView = [self hostView];
    if (!hostView || conversation.convID.length == 0) { return; }
    [self buildIfNeededInHost:hostView];

    _convID = conversation.convID;
    _host = [host copy];
    _userID = [userID copy];
    _conversation = conversation;

    BOOL isGroup = conversation.isGroup;
    NSString *title = conversation.displayName;
    NSString *avatarURL = IMMediaFullURL(isGroup ? conversation.avatarURL : conversation.peerAvatarURL, host);
    NSString *avatarSeed = isGroup ? conversation.convID : conversation.peer;
    BOOL previewEnabled = isGroup ? IMNotificationSettings.shared.groupType.preview : IMNotificationSettings.shared.privateType.preview;
    NSString *sender = isGroup
        ? [IMRemarkStore.sharedStore displayNameForUser:message.from
                                                fallback:(message.fromNickname.length > 0 ? message.fromNickname : message.from)]
        : nil;

    IMInAppBannerContent *content = IMInAppBannerContentBuild(title, isGroup, avatarURL, avatarSeed, previewEnabled,
        message.contentType, message.caption, message.content, message.duration, sender);

    [_avatar im_setAvatarURL:content.avatarURL seed:content.avatarSeed displayName:content.avatarDisplayName];
    _titleLabel.text = content.title;
    _bodyLabel.text = content.body;

    if (_visible) {
        // 已在显示：原地换内容，不重新滑入，只重新计时（§1.2「原地换内容并重新计时，不叠第二条」）。
        [self armAutoDismissTimer];
        return;
    }
    _visible = YES;
    _card.hidden = NO;
    [hostView layoutIfNeeded]; // 先按隐藏位置摆好，动画才有"从上滑入"的起点

    CGFloat estimatedHeight = [_card systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    _hiddenTopConstant = -(estimatedHeight + kIMBannerSideMargin + 40);
    _topConstraint.constant = _hiddenTopConstant;
    _card.alpha = 1;
    [hostView layoutIfNeeded];

    _topConstraint.constant = kIMBannerSideMargin;
    if (IMPowerSaving.shared.animationsEffective) {
        [UIView animateWithDuration:kIMBannerSlideDuration delay:0
             usingSpringWithDamping:0.85 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ [hostView layoutIfNeeded]; } completion:nil];
    } else {
        [hostView layoutIfNeeded];
    }
    [self armAutoDismissTimer];
}

#pragma mark - 收起

- (void)dismissAnimated:(BOOL)animated {
    if (!_visible) { return; }
    _visible = NO;
    [self cancelAutoDismissTimer];
    _convID = nil;
    _conversation = nil;

    UIView *hostView = _card.superview;
    void (^cleanup)(void) = ^{
        // 收起动画的 0.25 秒里若来了新消息、横幅已重新滑出（_visible 又变 YES），这里不能再把它藏掉
        //（/code-review 2026-09-29：否则新横幅刚出现就消失）。
        if (self->_visible) { return; }
        self->_card.hidden = YES;
        self->_card.alpha = 0;
    };
    if (animated && IMPowerSaving.shared.animationsEffective && hostView) {
        _topConstraint.constant = _hiddenTopConstant;
        [UIView animateWithDuration:kIMBannerSlideDuration animations:^{
            [hostView layoutIfNeeded];
            self->_card.alpha = 0;
        } completion:^(BOOL finished) { cleanup(); }];
    } else {
        cleanup();
    }
}

#pragma mark - 计时（按住暂停，松手/收起恢复或作废）

- (void)armAutoDismissTimer {
    [self cancelAutoDismissTimer];
    _remainingInterval = kIMBannerAutoDismissDelay;
    [self resumeAutoDismissTimer];
}

- (void)resumeAutoDismissTimer {
    if (_dismissTimer || _remainingInterval <= 0) { return; }
    _timerArmedAt = CFAbsoluteTimeGetCurrent();
    _dismissTimer = [NSTimer timerWithTimeInterval:_remainingInterval target:self
                                            selector:@selector(autoDismissFired) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_dismissTimer forMode:NSRunLoopCommonModes];
}

- (void)pauseAutoDismissTimer {
    if (!_dismissTimer) { return; }
    NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _timerArmedAt;
    _remainingInterval = MAX(0, _remainingInterval - elapsed);
    [_dismissTimer invalidate];
    _dismissTimer = nil;
}

- (void)cancelAutoDismissTimer {
    [_dismissTimer invalidate];
    _dismissTimer = nil;
    _remainingInterval = 0;
}

- (void)autoDismissFired {
    _dismissTimer = nil;
    [self dismissAnimated:YES];
}

#pragma mark - 触摸/手势

- (void)handleTouchDown {
    [self pauseAutoDismissTimer]; // 手指按住时不计时
}

- (void)handleTouchUpInside {
    // 松手且落点仍在卡片内 = 点击：进入该会话（与点会话列表行同一路径），横幅收起。
    IMConversation *conversation = _conversation;
    NSString *host = _host;
    NSString *userID = _userID;
    [self dismissAnimated:YES];
    if (conversation && host.length > 0 && userID.length > 0) {
        [IMConversationRouter openConversation:conversation host:host userID:userID];
    }
}

- (void)handleTouchEndedWithoutTap {
    [self resumeAutoDismissTimer]; // 松手但不构成点击（拖出卡片外/被手势取消）：恢复计时
}

- (void)handleSwipeUp {
    [self dismissAnimated:YES];
}

#pragma mark - 会话被打开（不论是否经由本横幅）

- (void)presenceChanged:(NSNotification *)note {
    NSString *viewingConvID = note.userInfo[IMChatPresenceConvIDKey];
    if (viewingConvID.length > 0 && _convID.length > 0 && [viewingConvID isEqualToString:_convID]) {
        [self dismissAnimated:YES];
    }
}

@end

@implementation IMInAppBannerView

+ (void)showForConversation:(IMConversation *)conversation message:(IMMessageModel *)message
                        host:(NSString *)host userID:(NSString *)userID {
    [IMInAppBannerPresenter.shared showForConversation:conversation message:message host:host userID:userID];
}

+ (void)dismiss {
    [IMInAppBannerPresenter.shared dismissAnimated:YES];
}

@end
