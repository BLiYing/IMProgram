//  IMLoginKeyboardTests.m
//  登录页：展开「服务器地址」后点进输入框，键盘弹出不能盖住它（登录页是一列堆叠、没有滚动容器，靠整列上移让位）。

#import <XCTest/XCTest.h>
#import "IMLoginViewController.h"

@interface IMLoginViewController (IMLKTesting)
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userIDField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *nicknameField;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, assign) CGFloat keyboardTop;
- (void)hostToggleTapped;
- (void)registerTabTapped;
@end

@interface IMLoginKeyboardTests : XCTestCase
@end

@implementation IMLoginKeyboardTests

- (void)spin:(NSTimeInterval)s { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

- (void)postKeyboardTop:(CGFloat)top height:(CGFloat)height screen:(CGFloat)screen {
    NSDictionary *info = @{
        UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:CGRectMake(0, top, 375, height)],
        UIKeyboardAnimationDurationUserInfoKey: @0.0,
    };
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil userInfo:info];
}

- (void)test_上移量_纯函数 {
    XCTAssertEqual(IMLoginKeyboardLift(300, 500), 0, @"输入框本来就在键盘上方，不动");
    XCTAssertEqual(IMLoginKeyboardLift(488, 500), 0, @"刚好留满 12pt 空隙，不动");
    XCTAssertEqual(IMLoginKeyboardLift(500, 500), 12, @"贴着键盘上沿时要再抬 12pt 留空隙");
    XCTAssertEqual(IMLoginKeyboardLift(520, 331), 201, @"被键盘盖住：抬到下沿离键盘 12pt");
}

- (UIWindow *)windowWith:(IMLoginViewController *)vc {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; } }
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    w.frame = CGRectMake(0, 0, 375, 667);
    w.rootViewController = vc;
    [w makeKeyAndVisible];
    return w;
}

/// 小屏（iPhone SE 高度）+ 336pt 键盘：服务器地址框下沿必须在键盘上沿之上；收起键盘后整列复位。
- (void)test_键盘弹出_服务器地址框不被盖住 {
    IMLoginViewController *vc = [IMLoginViewController new];
    UIWindow *w = [self windowWith:vc];
    [self spin:0.3];
    [vc hostToggleTapped]; // 展开「服务器地址」
    [vc.view layoutIfNeeded];

    CGFloat kbTop = 667 - 336;
    CGRect before = [w convertRect:vc.hostField.bounds fromView:vc.hostField];
    XCTAssertGreaterThan(CGRectGetMaxY(before), kbTop, @"前提：不处理键盘时，地址框下沿会落进键盘区");

    XCTAssertTrue([vc.hostField becomeFirstResponder]);
    [self spin:0.6]; // 模拟器无软键盘时系统自己也会发一次「键盘收起」通知，先让它过去，再发我们的
    [self postKeyboardTop:kbTop height:336 screen:667];
    [self spin:0.4];

    XCTAssertTrue(vc.hostField.isFirstResponder, @"通知过后仍是第一响应者");
    CGRect after = [w convertRect:vc.hostField.bounds fromView:vc.hostField];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(after), kbTop + 0.5, @"键盘弹出后地址框必须在键盘上沿之上");
    XCTAssertGreaterThan(CGRectGetMinY(after), 0, @"地址框自己不能被顶出屏幕上沿");

    // 同一个键盘下切到别的输入框：系统不再发键盘通知，靠开始编辑事件重算
    [vc.hostField resignFirstResponder];
    XCTAssertTrue([vc.passwordField becomeFirstResponder]);
    // 真机上同一键盘下切换输入框，键盘始终在、不会发「收起」通知；模拟器没有软键盘，resign 会同步发一次收起通知
    // 把记录的键盘上沿冲掉，这里还原成「键盘一直在」的状态。
    vc.keyboardTop = kbTop;
    [vc.passwordField sendActionsForControlEvents:UIControlEventEditingDidBegin]; // 无软键盘的模拟器上 becomeFirstResponder 不一定触发
    // 这里不能 spin：系统异步发的「键盘收起」通知会把键盘上沿再次冲掉。
    // 约束布局在 layoutIfNeeded 里同步算出 frame（动画只作用于图层），所以立刻断言即可。
    CGRect pwd = [w convertRect:vc.passwordField.bounds fromView:vc.passwordField];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(pwd), kbTop + 0.5, @"切到密码框后它同样不能被盖住");
    XCTAssertGreaterThan(CGRectGetMinY(pwd), 0);

    // 键盘收起：复位
    [vc.passwordField resignFirstResponder];
    [self postKeyboardTop:667 height:336 screen:667];
    [self spin:0.4];
    CGRect rest = [w convertRect:vc.hostField.bounds fromView:vc.hostField];
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(rest), CGRectGetMaxY(before), 0.5, @"键盘收起后整列回到原位");

    w.hidden = YES;
}

/// 注册页签：编辑昵称 / 密码时，「注册」按钮也要在键盘之上（不能只保证输入框可见）。
- (void)test_注册页_键盘弹出_注册按钮不被盖住 {
    IMLoginViewController *vc = [IMLoginViewController new];
    UIWindow *w = [self windowWith:vc];
    [self spin:0.3];
    [vc registerTabTapped];
    [vc.view layoutIfNeeded];

    CGFloat kbTop = 667 - 336;
    CGRect before = [w convertRect:vc.registerButton.bounds fromView:vc.registerButton];
    XCTAssertGreaterThan(CGRectGetMaxY(before), kbTop, @"前提：不处理键盘时，注册按钮会落进键盘区");

    for (UITextField *f in @[vc.passwordField, vc.nicknameField]) {
        XCTAssertTrue([f becomeFirstResponder]);
        [self spin:0.6];
        [self postKeyboardTop:kbTop height:336 screen:667];
        [self spin:0.4];
        CGRect btn = [w convertRect:vc.registerButton.bounds fromView:vc.registerButton];
        CGRect fr = [w convertRect:f.bounds fromView:f];
        XCTAssertLessThanOrEqual(CGRectGetMaxY(btn), kbTop + 0.5, @"注册按钮必须在键盘上沿之上");
        XCTAssertGreaterThan(CGRectGetMinY(fr), 0, @"输入框自己不能被顶出屏幕上沿");
        [f resignFirstResponder];
        [self postKeyboardTop:667 height:336 screen:667];
        [self spin:0.4];
    }
    w.hidden = YES;
}

/// 矮屏（横屏 / 大字号）放不下：输入框下沿宁可贴着键盘，也不能被顶出安全区上沿。
- (void)test_矮屏放不下_输入框不被顶出屏幕上沿 {
    IMLoginViewController *vc = [IMLoginViewController new];
    UIWindow *w = [self windowWith:vc];
    w.frame = CGRectMake(0, 0, 375, 320);
    [self spin:0.3];
    [vc hostToggleTapped];
    [vc.view layoutIfNeeded];

    XCTAssertTrue([vc.hostField becomeFirstResponder]);
    [self spin:0.6];
    [self postKeyboardTop:320 - 260 height:260 screen:320]; // 键盘占了大半屏
    [self spin:0.4];

    CGRect r = [w convertRect:vc.hostField.bounds fromView:vc.hostField];
    CGFloat safeTop = vc.view.safeAreaLayoutGuide.layoutFrame.origin.y;
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(r), safeTop - 0.5, @"输入框自己不能被顶出安全区上沿");
    w.hidden = YES;
}

@end
