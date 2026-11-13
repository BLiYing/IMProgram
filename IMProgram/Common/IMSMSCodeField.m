//  IMSMSCodeField.m

#import "IMSMSCodeField.h"
#import "IMLocalization.h"
#import "IMHTTPService+Phone.h" // IMSMSSendResult / IMSMSRetryAfterFromError

static CGFloat const kIMSMSSendRightInset = 8;

@interface IMSMSCodeField ()
@property (nonatomic, strong) UIColor *sendTint;
@property (nonatomic, strong, readwrite) UIButton *sendButton;
@property (nonatomic, assign, readwrite, getter=isSending) BOOL sending;
@property (nonatomic, strong, nullable) NSTimer *timer;
@end

@implementation IMSMSCodeField

- (instancetype)initWithTint:(UIColor *)tint {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO; // 宿主一律用约束摆放（表格行 / 栈 / 卡片）
        _sendTint = tint;
        _clock = [IMResendClock new];
        _sendAllowed = YES;
        self.placeholder = IMLocalized(@"login.sms_code.placeholder");
        self.keyboardType = UIKeyboardTypeNumberPad;
        self.textContentType = UITextContentTypeOneTimeCode;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.accessibilityHint = IMLocalized(@"login.sms_code.six_digits");
        [self addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self buildSendButton];
        [self refreshSendButton];
    }
    return self;
}

- (void)buildSendButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:15];
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, kIMSMSSendRightInset);
    b.accessibilityIdentifier = @"sms.send_code";
    [b addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton = b;
    self.rightView = b;
    self.rightViewMode = UITextFieldViewModeAlways;
}

- (void)setClock:(IMResendClock *)clock {
    _clock = clock ?: [IMResendClock new];
    [self refreshSendButton];
}

- (void)setSendAllowed:(BOOL)sendAllowed {
    _sendAllowed = sendAllowed;
    [self refreshSendButton];
}

/// 组词期间不改写；其余只留数字、最多 6 位（粘贴整条短信也能取出码）。
- (void)textChanged {
    if (self.markedTextRange) { return; }
    NSString *clean = IMSMSCodeSanitize(self.text);
    if (![clean isEqualToString:self.text ?: @""]) { self.text = clean; }
}

- (void)sendTapped {
    if (!self.sendButton.enabled) { return; }
    if (self.onSend) { self.onSend(); }
}

- (void)beginSending {
    self.sending = YES;
    [self refreshSendButton];
}

- (void)finishSending {
    self.sending = NO;
    [self refreshSendButton];
}

- (NSString *)applySendResult:(IMSMSSendResult *)result error:(NSError *)error sameTarget:(BOOL)sameTarget {
    NSString *message = nil;
    if (result && sameTarget) {
        [self.clock noteSentWithResendAfter:result.resendAfter now:[NSDate date]];
    } else if (error) {
        NSInteger retry = IMSMSRetryAfterFromError(error);
        if (sameTarget) { [self.clock noteFailureCode:error.code retryAfter:retry now:[NSDate date]]; }
        message = IMSMSSendErrorMessage(error.code, retry, IMErrorMessageOrFallback(error, IMLocalized(@"common.action_failed")));
    }
    [self finishSending];
    return message;
}

- (void)refreshSendButton {
    NSInteger left = [self.clock secondsLeftAt:[NSDate date]];
    BOOL enabled = self.sendAllowed && !self.sending && left == 0;
    [UIView performWithoutAnimation:^{
        [self.sendButton setTitle:IMSMSSendButtonTitle(left, self.clock.sentOnce) forState:UIControlStateNormal];
        [self.sendButton setTitleColor:self.sendTint forState:UIControlStateNormal];
        [self.sendButton setTitleColor:UIColor.tertiaryLabelColor forState:UIControlStateDisabled];
        self.sendButton.enabled = enabled;
        [self.sendButton sizeToFit];
        [self.sendButton layoutIfNeeded];
    }];
    [self setNeedsLayout];
    if (left > 0) { [self startTimerIfNeeded]; } else { [self stopTimer]; }
}

#pragma mark - Timer（只在窗口里跑）

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) { [self refreshSendButton]; } else { [self stopTimer]; }
}

- (void)startTimerIfNeeded {
    if (!self.window || self.timer.isValid) { return; }
    __weak typeof(self) ws = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [ws refreshSendButton]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)dealloc { [_timer invalidate]; }

@end
