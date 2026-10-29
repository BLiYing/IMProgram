//  IMProfileEditKeyboardTests.m
//  编辑资料页：键盘弹出后「个性签名」（表单最后一格）不能被键盘盖住——表单装在滚动容器里，键盘通知给底部让位并把输入框滚进可见区。

#import <XCTest/XCTest.h>
#import "IMProfileEditViewController.h"
#import "IMHTTPService.h"

@interface IMPEStub : NSURLProtocol
@end
@implementation IMPEStub
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.path isEqualToString:@"/api/v1/users/me"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSDictionary *reply = @{ @"code": @0, @"data": @{ @"user_id": @"pe-me", @"username": @"liying", @"nickname": @"李颖", @"phone": @"13800000000", @"bio": @"慢慢来" } };
    NSData *d = [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:d];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMProfileEditViewController (IMPETesting)
@property (nonatomic, strong) UITextView *bioView;
@property (nonatomic, strong) UIScrollView *editScroll;
@end

@interface IMProfileEditKeyboardTests : XCTestCase
@end

@implementation IMProfileEditKeyboardTests

- (void)spin:(NSTimeInterval)s { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

/// 小屏（iPhone SE 高度）+ 336pt 键盘：签名输入框下沿必须在键盘上沿之上。
- (void)test_键盘弹出_个性签名不被盖住 {
    IMHTTPService *svc = IMHTTPService.sharedService;
    svc.host = @"127.0.0.1:59391";
    [svc setValue:@"pe-token" forKey:@"currentToken"];
    [svc setValue:@"pe-me" forKey:@"tokenUserID"];
    [svc setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"tokenFetchedAt"];
    [NSURLProtocol registerClass:IMPEStub.class];

    IMProfileEditViewController *vc = [[IMProfileEditViewController alloc] initWithHost:svc.host userID:@"pe-me"];
    vc.startsEditing = YES;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; } }
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    w.frame = CGRectMake(0, 0, 375, 667);
    w.rootViewController = [[UINavigationController alloc] initWithRootViewController:vc];
    [w makeKeyAndVisible];
    [self spin:0.8];

    // 先确认没有键盘时，签名框在小屏上确实落在键盘区里（否则这条测试什么也没证明）
    CGFloat kbTop = 667 - 336;
    CGRect before = [w convertRect:vc.bioView.bounds fromView:vc.bioView];
    XCTAssertGreaterThan(CGRectGetMaxY(before), kbTop, @"前提：不处理键盘时，签名框下沿会落进键盘区");

    XCTAssertTrue([vc.bioView becomeFirstResponder], @"签名框应能成为第一响应者");
    XCTAssertTrue(vc.bioView.isFirstResponder);
    [self spin:0.6]; // 模拟器无软键盘时系统自己也会发一次「键盘收起」通知，先让它过去，再发我们的
    NSDictionary *info = @{
        UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:CGRectMake(0, kbTop, 375, 336)],
        UIKeyboardAnimationDurationUserInfoKey: @0.0,
    };
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil userInfo:info];
    [self spin:0.5];

    XCTAssertTrue(vc.bioView.isFirstResponder, @"通知过后仍是第一响应者");
    CGRect after = [w convertRect:vc.bioView.bounds fromView:vc.bioView];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(after), kbTop + 0.5, @"键盘弹出后签名框必须被滚到键盘上沿之上");
    XCTAssertGreaterThanOrEqual(vc.editScroll.contentInset.bottom, 300, @"底部给键盘让位");

    // 键盘收起：让位还原
    NSDictionary *hide = @{
        UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:CGRectMake(0, 667, 375, 336)],
        UIKeyboardAnimationDurationUserInfoKey: @0.0,
    };
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil userInfo:hide];
    [self spin:0.3];
    XCTAssertEqualWithAccuracy(vc.editScroll.contentInset.bottom, 0, 0.5);

    w.hidden = YES;
    [NSURLProtocol unregisterClass:IMPEStub.class];
}

@end
