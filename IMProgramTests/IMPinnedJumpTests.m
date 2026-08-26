//  IMPinnedJumpTests.m
//  点置顶横幅/置顶列表行跳转前的「原消息还在吗」判定（G0，用户实测 2026-08-26）：
//  置顶一条 → 立刻撤回 → 横幅可能还没收敛（reloadPinnedBanner 是 best-effort / msg_op 帧未到），
//  此时点它必须提示「原消息已被撤回」，而不是静默滚到那条「撤回了一条消息」的系统行上闪一下。
//  判据与 Web `src/App.pinnedBanner.test.tsx` 对齐（parity）。
//  app-hosted 测试，符号由宿主 App 提供；判定抽成文件级纯函数，免构造依赖数据库的真 VC
//  （同 IMChatStackRoutingTests 的套路）。

#import <XCTest/XCTest.h>
#import "IMMessageModel.h"

// IMChatViewController+PinnedBanner.m 里的文件级纯函数。
FOUNDATION_EXPORT BOOL IMPinnedTargetRecalled(NSArray<IMMessageModel *> *messages, int64_t convSeq);

@interface IMPinnedJumpTests : XCTestCase
@end

@implementation IMPinnedJumpTests

static IMMessageModel *Msg(int64_t convSeq, int64_t recalledAt) {
    IMMessageModel *m = [[IMMessageModel alloc] init];
    m.convSeq = convSeq;
    m.recalledAt = recalledAt;
    return m;
}

/// 核心场景：置顶后立刻撤回，横幅还停在旧集合上 → 判定为"已撤回"，调用方提示而非跳转。
- (void)testRecalledTargetIsDetected {
    NSArray *messages = @[ Msg(6, 0), Msg(7, 1700000000000), Msg(8, 0) ];
    XCTAssertTrue(IMPinnedTargetRecalled(messages, 7));
}

/// 正常置顶消息 → 照常跳转（不误报，否则置顶横幅会变成永远点不动）。
- (void)testLiveTargetJumpsNormally {
    NSArray *messages = @[ Msg(6, 0), Msg(7, 0) ];
    XCTAssertFalse(IMPinnedTargetRecalled(messages, 7));
}

/// 本地压根没有这条（很早的置顶还没加载到 / 已被删除）→ 不由本判定接管，
/// 交给 jumpToConvSeq: 自己分辨「原消息不在本地」还是「原消息已被删除」。
- (void)testMissingTargetFallsThrough {
    XCTAssertFalse(IMPinnedTargetRecalled(@[ Msg(6, 0) ], 7));
    XCTAssertFalse(IMPinnedTargetRecalled(@[], 7));
    XCTAssertFalse(IMPinnedTargetRecalled(nil, 7));
}

/// 位点非法（0/负）→ 不当作撤回；跳转侧会走既有的无效位点分支。
- (void)testInvalidSeqIsNotRecalled {
    XCTAssertFalse(IMPinnedTargetRecalled(@[ Msg(0, 1700000000000) ], 0));
    XCTAssertFalse(IMPinnedTargetRecalled(@[ Msg(7, 1700000000000) ], -1));
}

@end
