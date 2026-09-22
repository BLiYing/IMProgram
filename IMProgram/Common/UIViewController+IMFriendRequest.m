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
@end

@implementation IMFriendHelloLimiter
- (instancetype)initWithField:(UITextField *)field {
    self = [super init];
    if (self) {
        _field = field;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
                                                   name:UITextFieldTextDidChangeNotification object:field];
    }
    return self;
}
- (void)changed:(NSNotification *)note {
    UITextField *f = self.field;
    // 有联想输入（markedTextRange 非空）时不动：拼音打到一半就截会把候选打断。
    if (!f || f.markedTextRange) { return; }
    NSString *t = f.text ?: @"";
    if ((NSInteger)t.length <= kIMFriendHelloMaxRunes) { return; }
    // 按**字符簇**截（composedCharacterRange）：emoji / 组合字符按 length 截会切出半个字符。
    NSRange r = [t rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, (NSUInteger)kIMFriendHelloMaxRunes)];
    f.text = [t substringWithRange:r];
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
        field.text = myNick.length > 0 ? [NSString stringWithFormat:@"我是%@", myNick] : @"";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
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
