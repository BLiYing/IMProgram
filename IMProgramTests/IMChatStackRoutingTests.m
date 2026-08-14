//  IMChatStackRoutingTests.m
//  聊天页统一入口的「导航折叠」纯逻辑测试：打开新会话时截掉栈里最底部的聊天页及其之上的页，
//  保证同一栈至多一个聊天页、从聊天页返回直达其下方（会话列表）。见 IMChatViewController.m。
//  app-hosted 测试，符号由宿主 App 提供；折叠核心抽为文件级纯函数并注入「是否聊天页」谓词，免构造真 VC。

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

// IMChatViewController.m 里的文件级纯函数（无需引整个 VC 头 / 无需真实数据库上下文）。
FOUNDATION_EXPORT NSArray<UIViewController *> *
IMChatCollapsedStack(NSArray<UIViewController *> *stack,
                     UIViewController *newChat,
                     BOOL (^isChatController)(UIViewController *vc));

@interface IMChatStackRoutingTests : XCTestCase
@end

@implementation IMChatStackRoutingTests

/// 生产用 isKindOfClass:IMChatViewController；测试用 restorationIdentifier==@"chat" 冒充聊天页，
/// 这样无需构造依赖数据库的真 IMChatViewController 即可覆盖折叠决策。
static UIViewController *VC(NSString *kind) {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.restorationIdentifier = kind;
    return vc;
}

static BOOL (^kIsChat)(UIViewController *) = ^BOOL(UIViewController *vc) {
    return [vc.restorationIdentifier isEqualToString:@"chat"];
};

/// 场景一（本次核心需求）：[列表, 群聊A, 资料B] 打开新会话C → 截掉 A 及其上的 B → [列表, C]。
/// 从 C 返回直达会话列表，栈里不再同时有两个聊天页。
- (void)testCollapsesGroupChatAndProfileWhenOpeningNewChat {
    UIViewController *list = VC(@"list");
    UIViewController *newChat = VC(@"chat");
    NSArray *stack = @[ list, VC(@"chat"), VC(@"detail") ];

    NSArray *result = IMChatCollapsedStack(stack, newChat, kIsChat);

    XCTAssertEqual(result.count, 2u);
    XCTAssertEqualObjects(result[0], list);
    XCTAssertEqualObjects(result[1], newChat);
}

/// 栈里无聊天页（如 [列表, 群列表]）→ 不折叠，等价普通 push（原栈 + 新页），保留原入口返回语义。
- (void)testPlainPushWhenNoChatInStack {
    UIViewController *list = VC(@"list");
    UIViewController *groupList = VC(@"groupList");
    UIViewController *newChat = VC(@"chat");
    NSArray *stack = @[ list, groupList ];

    NSArray *result = IMChatCollapsedStack(stack, newChat, kIsChat);

    XCTAssertEqual(result.count, 3u);
    XCTAssertEqualObjects(result[0], list);
    XCTAssertEqualObjects(result[1], groupList);
    XCTAssertEqualObjects(result[2], newChat);
}

/// 根即会话列表、直接点行开聊天 [列表] → [列表, C]。
- (void)testPushOntoBareList {
    UIViewController *list = VC(@"list");
    UIViewController *newChat = VC(@"chat");

    NSArray *result = IMChatCollapsedStack(@[ list ], newChat, kIsChat);

    XCTAssertEqual(result.count, 2u);
    XCTAssertEqualObjects(result[0], list);
    XCTAssertEqualObjects(result[1], newChat);
}

/// 截取以**最底部**聊天页为界：即便栈里已（异常地）存在多个聊天页，也一并截掉，收敛到至多一个。
- (void)testCutsAtDeepestChatCollapsingAllChats {
    UIViewController *list = VC(@"list");
    UIViewController *newChat = VC(@"chat");
    NSArray *stack = @[ list, VC(@"chat"), VC(@"detail"), VC(@"chat") ];

    NSArray *result = IMChatCollapsedStack(stack, newChat, kIsChat);

    XCTAssertEqual(result.count, 2u);
    XCTAssertEqualObjects(result[0], list);
    XCTAssertEqualObjects(result[1], newChat);
}

/// 空栈兜底：只落新页（不崩）。
- (void)testEmptyStack {
    UIViewController *newChat = VC(@"chat");
    NSArray *result = IMChatCollapsedStack(@[], newChat, kIsChat);
    XCTAssertEqual(result.count, 1u);
    XCTAssertEqualObjects(result[0], newChat);
}

@end
