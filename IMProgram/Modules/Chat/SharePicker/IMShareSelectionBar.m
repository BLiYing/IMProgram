//  IMShareSelectionBar.m

#import "IMShareSelectionBar.h"
#import "IMShareSelection.h"
#import "IMSelectedChipStrip.h"
#import "IMConversation.h"
#import "IMLocalization.h"
#import "IMTheme.h"

static const CGFloat kIMShareBarChipTop = 10;

IMSelectedChip *IMShareChipForConversation(IMConversation *c) {
    NSString *url = c.isGroup ? c.avatarURL : c.peerAvatarURL;
    NSString *seed = c.isGroup ? c.convID : (c.peer ?: c.convID);
    return [IMSelectedChip chipWithID:c.convID avatarURL:url seed:seed ?: @"" name:c.displayName];
}
static const CGFloat kIMShareBarSendHeight = 34;

@implementation IMShareSelectionBar {
    IMSelectedChipStrip *_strip;
    UILabel *_hint;
    UIButton *_send;
    UIView *_hairline;
}

+ (CGFloat)contentHeight { return IMSelectedChipStrip.chipHeight + kIMShareBarChipTop + 6; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = IMTheme.surface;

        _hairline = [UIView new];
        _hairline.translatesAutoresizingMaskIntoConstraints = NO;
        _hairline.backgroundColor = IMTheme.separator;
        [self addSubview:_hairline];

        _strip = [IMSelectedChipStrip new];
        _strip.translatesAutoresizingMaskIntoConstraints = NO;
        _strip.leadingInset = IMTheme.space3;
        _strip.chipTop = kIMShareBarChipTop;
        __weak typeof(self) ws = self;
        _strip.onRemove = ^(NSString *convID) { if (ws.onRemove) { ws.onRemove(convID); } };
        [self addSubview:_strip];

        _hint = [UILabel new];
        _hint.translatesAutoresizingMaskIntoConstraints = NO;
        _hint.font = [UIFont systemFontOfSize:13];
        _hint.textColor = IMTheme.textSecondary;
        _hint.numberOfLines = 2;
        [self addSubview:_hint];

        _send = [UIButton buttonWithType:UIButtonTypeCustom];
        _send.translatesAutoresizingMaskIntoConstraints = NO;
        _send.backgroundColor = IMTheme.accent;
        _send.layer.cornerRadius = kIMShareBarSendHeight / 2;
        _send.layer.masksToBounds = YES;
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
        cfg.baseForegroundColor = UIColor.whiteColor;
        cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
            NSMutableDictionary *out = [attrs mutableCopy];
            out[NSFontAttributeName] = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            return out;
        };
        _send.configuration = cfg;
        [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
        [_send setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_send setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:_send];

        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_hairline.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_hairline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_hairline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

            [_strip.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_strip.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [_strip.trailingAnchor constraintEqualToAnchor:_send.leadingAnchor constant:-IMTheme.space2],
            [_strip.heightAnchor constraintEqualToConstant:IMShareSelectionBar.contentHeight],
            [_strip.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

            [_hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:IMTheme.space4],
            [_hint.trailingAnchor constraintEqualToAnchor:_send.leadingAnchor constant:-IMTheme.space2],
            [_hint.centerYAnchor constraintEqualToAnchor:_strip.centerYAnchor],

            [_send.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-IMTheme.space3],
            [_send.centerYAnchor constraintEqualToAnchor:_strip.centerYAnchor constant:-4],
            [_send.heightAnchor constraintEqualToConstant:kIMShareBarSendHeight],
        ]];
    }
    return self;
}

- (void)reloadWithSelection:(IMShareSelection *)selection scrollToEnd:(BOOL)scrollToEnd {
    NSMutableArray<IMSelectedChip *> *chips = [NSMutableArray arrayWithCapacity:selection.count];
    for (IMConversation *c in selection.conversations) { [chips addObject:IMShareChipForConversation(c)]; }
    [_strip setChips:chips scrollToEnd:scrollToEnd];
    BOOL empty = selection.count == 0;
    _strip.hidden = empty;
    _hint.hidden = !empty;
    _hint.text = IMLocalizedFormat(@"share.picker.bar_hint", (long)selection.limit);
    NSString *title = empty ? IMLocalized(@"common.send")
                            : IMLocalizedFormat(@"forward.picker.send_count", (long)selection.count);
    [UIView performWithoutAnimation:^{
        [self->_send setTitle:title forState:UIControlStateNormal];
        [self->_send layoutIfNeeded];
    }];
    _send.enabled = !empty;
    _send.alpha = empty ? 0.4 : 1.0;
}

- (void)sendTapped { if (self.onSend) { self.onSend(); } }

@end
