//  IMAccessibilityLabelTests.m
//  两处读屏（VoiceOver）念错 / 念不出的缺口，2026-09-11 跑会话内搜索 UI 测试时顺带发现：
//  ① 聊天页右上头像按钮：页面把「X的聊天详情」挂在 UIBarButtonItem 上，注入的液态标题栏没透传，按钮 label 为空；
//  ② 详情页操作排：label 被拿来当动作键（"search"），读屏念出英文。
//  两条都是**静默**的——画面和点击全都正常，只有读屏用户听得出来，所以钉在单测里。

#import <XCTest/XCTest.h>

#import "IMMainTabBarController.h"
#import "IMChatDetailViewController.h"

// 不引 +Private.h：它会带进 IMProgram-Swift.h，测试 target 没有这份生成头。只借用要测的那一个方法。
@interface IMChatDetailViewController (IMAccessibilityTesting)
- (UIButton *)actionPillButtonForSpec:(NSDictionary *)spec;
@end

@interface IMAccessibilityLabelTests : XCTestCase
@end

@implementation IMAccessibilityLabelTests

static UIButton *IMFindButtonLabeled(UIView *root, NSString *label) {
    if ([root isKindOfClass:UIButton.class] && [root.accessibilityLabel isEqualToString:label]) {
        return (UIButton *)root;
    }
    for (UIView *sub in root.subviews) {
        UIButton *hit = IMFindButtonLabeled(sub, label);
        if (hit) { return hit; }
    }
    return nil;
}

/// 纯图标右钮没有标题可退：item 上的 accessibilityLabel 不带到栏上的按钮，读屏就只剩「按钮」。
- (void)test_注入标题栏把纯图标右钮的无障碍标签带到按钮上 {
    Class navClass = NSClassFromString(@"IMMainNavigationController");
    XCTAssertNotNil(navClass, @"导航容器类名变了，这条要跟着改");
    UIViewController *page = [UIViewController new];
    UINavigationController *nav = [[navClass alloc] initWithRootViewController:[UIViewController new]];
    [nav pushViewController:page animated:NO];

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle"]
                                                             style:UIBarButtonItemStylePlain target:nil action:nil];
    item.accessibilityLabel = @"张三的聊天详情";
    page.navigationItem.rightBarButtonItem = item;
    [page loadViewIfNeeded];
    [page im_refreshNavigationBar];

    XCTAssertNotNil(IMFindButtonLabeled(page.view, @"张三的聊天详情"),
                    @"注入的液态标题栏没把右钮的无障碍标签带过去");
}

/// label 念给人听（标题），identifier 给代码分派（动作键）——两者分开，改一个不伤另一个。
- (void)test_详情页操作排念标题_动作键放在identifier {
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initGroupWithHost:@"127.0.0.1:8099"
                                                                                   userID:@"u_a11y"
                                                                                   convID:@"g_a11y"
                                                                                groupName:@"无障碍测试群"
                                                                           groupAvatarURL:nil];
    UIButton *search = [vc actionPillButtonForSpec:@{@"t": @"搜索", @"s": @"magnifyingglass", @"a": @"search"}];
    XCTAssertEqualObjects(search.accessibilityLabel, @"搜索");
    // 字面量是有意的：UI 测试按 "detail.pill.search" 找按钮，这个拼法本身就是对外约定。
    XCTAssertEqualObjects(search.accessibilityIdentifier, @"detail.pill.search");

    UIButton *more = [vc actionPillButtonForSpec:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];
    XCTAssertEqualObjects(more.accessibilityLabel, @"更多");
    XCTAssertTrue([[more actionsForTarget:vc forControlEvent:UIControlEventTouchUpInside] containsObject:@"moreTapped:"],
                  @"「更多」要走锚点菜单，不能落进 pillTapped:");
}

@end
