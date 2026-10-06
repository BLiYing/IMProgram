//  UIViewController+IMFriendRequest.m
//  接口与收口理由见头文件。

#import "UIViewController+IMFriendRequest.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"
#import "IMHTTPService.h"
#import "IMAccountIdentity.h"

/// 与后端 `friend.MaxHelloRunes` 一致。服务端超长会**截断**而不是报错，端上先拦一道只是为了
/// 让用户当场知道写不下了，而不是发完才发现被剪掉半句。
static NSInteger const kIMFriendHelloMaxRunes = 50;

/// 输入框限长的小助手：UITextField 没有 maxLength，只能挂 delegate 或订阅通知。
/// 用通知而不是 delegate：alert 的 textField 交给外部 delegate 会和 UIAlertController 自己的
/// 校验（比如"空文本禁用按钮"）打架，而这里只需要截断。
@interface IMFriendHelloLimiter : NSObject
@property (nonatomic, weak) UITextField *field;
@property (nonatomic, strong) UILabel *counter;
@property (nonatomic, strong) UIButton *clearBtn;
@property (nonatomic, strong) UIView *accessory;
@end

/// 按 Unicode 标量（= 服务端 rune）计数。
static NSUInteger IMHelloRuneCount(NSString *t) {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < t.length; n++) {
        unichar c = [t characterAtIndex:i];
        i += (CFStringIsSurrogateHighCharacter(c) && i + 1 < t.length) ? 2 : 1;
    }
    return n;
}

/// 取前 max 个标量，且不把字符簇（emoji 修饰符/ZWJ/组合符）切半：先按标量定位，再向下对齐到簇边界。
static NSString *IMHelloTruncate(NSString *t, NSUInteger max) {
    NSUInteger i = 0, n = 0;
    while (i < t.length && n < max) {
        unichar c = [t characterAtIndex:i];
        i += (CFStringIsSurrogateHighCharacter(c) && i + 1 < t.length) ? 2 : 1;
        n++;
    }
    if (i >= t.length) { return t; }
    NSRange r = [t rangeOfComposedCharacterSequenceAtIndex:i];
    if (r.location < i) { i = r.location; } // i 落在簇中间 → 整簇丢弃
    return [t substringToIndex:i];
}

@implementation IMFriendHelloLimiter
- (instancetype)initWithField:(UITextField *)field {
    self = [super init];
    if (self) {
        _field = field;
        // 右侧「n/50」计数（与 Android 同格式），小号 tertiary 色。
        // UITextField 里系统 clearButton 与 rightView 同占右侧、clearButton 优先会把计数顶掉，
        // 所以关掉系统清除钮，改在 rightView 容器里自带一个清除钮 + 计数。
        UILabel *c = [[UILabel alloc] init];
        c.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        c.textColor = UIColor.tertiaryLabelColor;
        c.textAlignment = NSTextAlignmentRight;
        _counter = c;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        b.tintColor = UIColor.tertiaryLabelColor;
        b.accessibilityLabel = IMLocalized(@"common.clear");
        [b addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
        _clearBtn = b;
        _accessory = [[UIView alloc] init];
        [_accessory addSubview:b];
        [_accessory addSubview:c];
        field.clearButtonMode = UITextFieldViewModeNever;
        field.rightView = _accessory;
        field.rightViewMode = UITextFieldViewModeAlways;
        [self refresh];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshNote:)
                                                   name:UITextFieldTextDidBeginEditingNotification object:field];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshNote:)
                                                   name:UITextFieldTextDidEndEditingNotification object:field];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
                                                   name:UITextFieldTextDidChangeNotification object:field];
    }
    return self;
}
- (void)refresh {
    UITextField *f = self.field;
    NSString *text = f.text ?: @"";
    self.counter.text = [NSString stringWithFormat:@"%lu/%ld", (unsigned long)IMHelloRuneCount(text), (long)kIMFriendHelloMaxRunes];
    [self.counter sizeToFit];
    CGFloat cw = self.counter.bounds.size.width + 4; // 与文本留点间距
    CGFloat h = 24;
    BOOL showClear = f.isEditing && text.length > 0;
    self.clearBtn.hidden = !showClear;
    CGFloat bw = showClear ? 24 : 0;
    self.counter.frame = CGRectMake(bw, 0, cw, h);
    self.clearBtn.frame = CGRectMake(0, 0, bw, h);
    self.accessory.frame = CGRectMake(0, 0, bw + cw, h);
    [f setNeedsLayout];
}
- (void)refreshNote:(NSNotification *)note { [self refresh]; }
- (void)clearTapped {
    self.field.text = @"";
    [self refresh];
}
- (void)changed:(NSNotification *)note {
    UITextField *f = self.field;
    // 有联想输入（markedTextRange 非空）时不动：拼音打到一半就截会把候选打断。
    if (!f) { return; }
    if (f.markedTextRange) { [self refresh]; return; } // 只更新计数，不截断
    NSString *t = f.text ?: @"";
    if (IMHelloRuneCount(t) > (NSUInteger)kIMFriendHelloMaxRunes) {
        f.text = IMHelloTruncate(t, (NSUInteger)kIMFriendHelloMaxRunes);
    }
    [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@implementation UIViewController (IMFriendRequest)

- (void)im_askFriendRequestForUID:(NSString *)uid
                             name:(NSString *)name
                           onSent:(void (^)(BOOL))onSent {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || uid.length == 0) { return; }
    NSString *shown = name.length > 0 ? name : IMLocalized(@"friend.request.peer_fallback");
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:IMLocalized(@"common.add_friend")
                                            message:IMLocalizedFormat(@"friend.request.alert_message", shown)
                                     preferredStyle:UIAlertControllerStyleAlert];
    // 预填「我是<我的昵称>」（微信同款）：多数人不会自己想措辞，给个能直接发的默认值，
    // 比留空更可能真的带上信息。currentNickname 是登录后预热的**公开昵称**——这句会发出去，
    // 故绝不能取备注或任何本机显示名。
    NSString *myNick = IMHTTPService.sharedService.currentNickname;
    __block IMFriendHelloLimiter *limiter = nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = IMLocalized(@"friend.request.placeholder");
        field.text = myNick.length > 0 ? IMLocalizedFormat(@"friend.request.hello_prefill", myNick) : @"";
        field.returnKeyType = UIReturnKeySend;
        limiter = [[IMFriendHelloLimiter alloc] initWithField:field];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        limiter = nil; // 断开通知订阅
    }]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.send") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *hello = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        limiter = nil;
        [IMHTTPService.sharedService requestFriendWithToken:token peerID:uid hello:hello
                                                 completion:^(BOOL becameFriend, NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"friend.request.send_failed")]; return; }
            // becameFriend 时**不说**「已发送好友申请」——那会让用户误以为还要等对方通过。
            [self im_showToast:becameFriend ? IMLocalized(@"friend.request.became_friends") : IMLocalized(@"friend.request.sent")];
            if (onSent) { onSent(becameFriend); }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
