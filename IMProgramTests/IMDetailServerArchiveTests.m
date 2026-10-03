//  IMDetailServerArchiveTests.m
//  资料页归档页签「本地 ∪ 服务端」的并集规则（IMDetailArchiveUnion）。对称 Web `unionByConvSeq`。
//  错法静默：重复一行（页签里同一张图出现两次）或把本地那行换成服务端的瘦版本（字段丢了）。

#import <XCTest/XCTest.h>

#import "IMDetailServerArchive.h"
#import "IMMessageModel.h"
#import "IMMediaServerTimeline.h"

@interface IMDetailServerArchiveTests : XCTestCase
@end

@implementation IMDetailServerArchiveTests

static IMMessageModel *M(int64_t seq, NSString *fileName) {
    IMMessageModel *m = [IMMessageModel new];
    m.convSeq = seq; m.content = [NSString stringWithFormat:@"/u/%lld", seq]; m.contentType = @"file"; m.fileName = fileName;
    return m;
}

static NSArray<NSNumber *> *Seqs(NSArray<IMMessageModel *> *ms) {
    NSMutableArray *o = [NSMutableArray array];
    for (IMMessageModel *m in ms) { [o addObject:@(m.convSeq)]; }
    return o;
}

/// 按 convSeq 去重，**本地优先**（本地行字段更全）；服务端独有的补上。
- (void)test_去重且本地优先 {
    IMMessageModel *localRow = M(5, @"local.pdf");
    NSArray *u = IMDetailArchiveUnion(@[localRow], @[M(5, @"server.pdf"), M(9, @"s9.pdf")]);
    XCTAssertEqualObjects(Seqs(u), (@[@5, @9]));
    XCTAssertEqual(u[0], localRow);
    XCTAssertEqualObjects(((IMMessageModel *)u[0]).fileName, @"local.pdf");
}

/// convSeq<=0 的服务端项不收；服务端页内自己重复只收一次。
- (void)test_非正seq与页内重复不收 {
    NSArray *u = IMDetailArchiveUnion(@[], @[M(0, @"a"), M(7, @"b"), M(7, @"c")]);
    XCTAssertEqualObjects(Seqs(u), (@[@7]));
    XCTAssertEqualObjects(((IMMessageModel *)u[0]).fileName, @"b");
}

/// 服务端没有东西：原样返回本地（本地齐全时的行为不变）。
- (void)test_服务端为空原样返回 {
    NSArray *local = @[M(1, @"x")];
    XCTAssertTrue(IMDetailArchiveUnion(local, @[]) == local);
}

/// 删除后别让服务端那份把它复活：时间线剔除后，并集里就不会再有它。
- (void)test_删除后时间线剔除_不再复活 {
    IMMediaServerTimeline *t = [[IMMediaServerTimeline alloc] initWithConvID:@"g" kind:@"file" clearedUpTo:0];
    [t seedWithMessages:@[M(3, @"a"), M(5, @"b"), M(9, @"c")] hasMore:NO];
    [t removeMessagesWithConvSeqs:[NSSet setWithObjects:@5, @77, nil]];
    XCTAssertEqualObjects(Seqs(t.messages), (@[@3, @9]));
    // 并集：本地没有 5，但服务端那份也已剔除 → 不会因为「本地没有就收服务端」而复活
    NSArray *u = IMDetailArchiveUnion(@[M(3, @"a")], t.messages);
    XCTAssertEqualObjects(Seqs(u), (@[@3, @9]));
}

@end
