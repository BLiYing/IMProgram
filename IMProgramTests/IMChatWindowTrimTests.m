//  IMChatWindowTrimTests.m
//  窗口超出内存上限时「该丢几条」（IMChatWindowTrim）。
//
//  错法全是**静默**的：丢到锚点身上 → 保位没有参照物、画面跳一下；丢到待发件 → 刚发的消息从屏幕消失；
//  头部在用户正看着时被丢 → 视口内容被删。所以按「会怎么错」钉，用例名就是那个错法。

#import <XCTest/XCTest.h>

#import "IMChatWindowTrim.h"
#import "IMMessageModel.h"

@interface IMChatWindowTrimTests : XCTestCase
@end

@implementation IMChatWindowTrimTests

/// 造 n 条已上号的行（conv_seq 1..n），再在尾部追加 pending 条待发件（conv_seq=0）。
static IMMessageModel *Msg(int64_t seq) { IMMessageModel *m = [[IMMessageModel alloc] init]; m.convSeq = seq; return m; }

static NSArray<IMMessageModel *> *Seqs(NSInteger n, NSInteger pending) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger i = 1; i <= n; i++) { [a addObject:Msg(i)]; }
    for (NSInteger i = 0; i < pending; i++) { [a addObject:Msg(0)]; }
    return a;
}

#pragma mark - 尾部

/// 没超上限一条都不丢；刚好等于上限也不丢（超出才丢）。
- (void)test_尾部_未超上限不丢 {
    XCTAssertEqual(IMChatTailDropCount(Seqs(5, 0), 10, NSNotFound), 0);
    XCTAssertEqual(IMChatTailDropCount(Seqs(10, 0), 10, NSNotFound), 0);
    XCTAssertEqual(IMChatTailDropCount(@[], 10, NSNotFound), 0);
}

/// 超出多少丢多少，不多丢（多丢 = 白白让用户往下翻时重新读库）。
- (void)test_尾部_超出多少丢多少 {
    XCTAssertEqual(IMChatTailDropCount(Seqs(13, 0), 10, NSNotFound), 3);
}

/// 尾部是待发/失败件（conv_seq=0）：属于「最新一段」，碰到就停——**哪怕还没丢够**，
/// 否则用户刚发的消息会从屏幕上消失。
- (void)test_尾部_碰到待发件就停 {
    XCTAssertEqual(IMChatTailDropCount(Seqs(12, 1), 10, NSNotFound), 0, @"尾巴就是待发件：一条都不能丢");
    // 待发件之前的已上号行不会被越过去丢掉：停在第一个 seq<=0 处。
    NSArray<IMMessageModel *> *mixed = @[Msg(1), Msg(2), Msg(3), Msg(4), Msg(5), Msg(0), Msg(6), Msg(7)];
    XCTAssertEqual(IMChatTailDropCount(mixed, 4, NSNotFound), 2, @"只丢尾部连续的已上号行（7、6），遇到 0 停");
}

/// 不丢到锚点身上：丢了它，随后的保位就没有参照物、只能放弃补偿 → 又是一次跳变。
- (void)test_尾部_不丢到锚点身上 {
    // 13 条、上限 10 → 想丢 3；锚点在第 11 行（0 起）：丢 1 条后尾行号=11 仍 > 锚点？尾行号 12→丢后 11，
    // 再丢尾行号 11 <= 11 停。即最多丢 1 条。
    XCTAssertEqual(IMChatTailDropCount(Seqs(13, 0), 10, 11), 1);
    // 锚点就是尾行：一条都不丢。
    XCTAssertEqual(IMChatTailDropCount(Seqs(13, 0), 10, 12), 0);
    // 锚点远在顶部（上翻的常态）：不受影响。
    XCTAssertEqual(IMChatTailDropCount(Seqs(13, 0), 10, 2), 3);
}

#pragma mark - 头部

- (void)test_头部_未超上限不丢 {
    XCTAssertEqual(IMChatHeadDropCount(10, 10, NSNotFound), 0);
    XCTAssertEqual(IMChatHeadDropCount(3, 10, 0), 0);
}

- (void)test_头部_无参照时超出多少丢多少 {
    XCTAssertEqual(IMChatHeadDropCount(13, 10, NSNotFound), 3);
}

/// 用户滚太快、视口已越过要丢的那一段（锚点行号 < 要丢的条数）：一条都不丢——
/// 宁可这一轮窗口超标，也不能把用户正看着的行删掉。
- (void)test_头部_锚点落在要丢的那一段里一条都不丢 {
    XCTAssertEqual(IMChatHeadDropCount(13, 10, 0), 0);
    XCTAssertEqual(IMChatHeadDropCount(13, 10, 2), 0);
}

/// 锚点恰好在要丢的那一段之外（行号 == 要丢条数）：可以丢，丢完锚点行号减去丢弃数。
- (void)test_头部_锚点在丢弃段之外照丢 {
    XCTAssertEqual(IMChatHeadDropCount(13, 10, 3), 3);
    XCTAssertEqual(IMChatHeadDropCount(13, 10, 8), 3);
}

@end
