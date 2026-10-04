//  IMPendingMediaStoreTests.m
//  待发媒体本地暂存（IMPendingMediaStore）：落盘/读回/路径安全/upload_id 旁挂/清理。
//
//  错法的后果是**丢待发件**或**文件写到暂存目录之外**：键含 `/` 或 `..`、删主文件前没取旁挂路径（旁挂文件残留）、
//  覆盖旧副本失败（重试时读到旧字节）。所以按「会怎么错」钉。用真实 Application Support 下的暂存目录，
//  每个 clientMsgID 带 UUID，用例末清理。

#import <XCTest/XCTest.h>

#import "IMPendingMediaStore.h"

@interface IMPendingMediaStoreTests : XCTestCase
@end

@implementation IMPendingMediaStoreTests {
    IMPendingMediaStore *_store;
    NSMutableArray<NSString *> *_refs;
}

- (void)setUp { [super setUp]; _store = IMPendingMediaStore.shared; _refs = [NSMutableArray array]; }
- (void)tearDown { for (NSString *r in _refs) { [_store removeLocalRef:r]; } [super tearDown]; }

- (NSString *)cid { return [@"pm-test-" stringByAppendingString:NSUUID.UUID.UUIDString]; }

- (NSString *)track:(NSString *)ref { if (ref) { [_refs addObject:ref]; } return ref; }

static NSData *Bytes(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }

#pragma mark - 标识

/// 本地标识判定：必须有前缀且**前缀之后非空**（只有前缀不算）。
- (void)test_isLocalRef {
    XCTAssertTrue([IMPendingMediaStore isLocalRef:@"im-pending://a.jpg"]);
    XCTAssertFalse([IMPendingMediaStore isLocalRef:@"im-pending://"]);
    XCTAssertFalse([IMPendingMediaStore isLocalRef:@"https://x/a.jpg"]);
    XCTAssertFalse([IMPendingMediaStore isLocalRef:@""]);
    XCTAssertFalse([IMPendingMediaStore isLocalRef:nil]);
}

#pragma mark - 落盘与读回

- (void)test_落盘后能读回字节与大小 {
    NSString *ref = [self track:[_store storeData:Bytes("hello") forClientMsgID:[self cid] extension:@"jpg"]];
    XCTAssertTrue([IMPendingMediaStore isLocalRef:ref]);
    XCTAssertTrue([ref hasSuffix:@".jpg"]);
    XCTAssertEqualObjects([_store dataForLocalRef:ref], Bytes("hello"));
    XCTAssertEqual([_store byteSizeForLocalRef:ref], 5);
    XCTAssertNotNil([_store filePathForLocalRef:ref]);
}

/// 无扩展名也能存；空数据 / 空 clientMsgID 拒绝（返回 nil，不建空文件）。
- (void)test_无扩展名可存_空入参拒绝 {
    NSString *ref = [self track:[_store storeData:Bytes("x") forClientMsgID:[self cid] extension:nil]];
    XCTAssertNotNil(ref);
    XCTAssertNil([_store storeData:[NSData data] forClientMsgID:[self cid] extension:@"jpg"]);
    XCTAssertNil([_store storeData:Bytes("x") forClientMsgID:@"" extension:@"jpg"]);
}

/// 同一个 clientMsgID 再存：覆盖旧副本（重试时读到的必须是新字节，不是旧的）。
- (void)test_同键再存覆盖旧副本 {
    NSString *cid = [self cid];
    [self track:[_store storeData:Bytes("old") forClientMsgID:cid extension:@"bin"]];
    NSString *ref = [self track:[_store storeData:Bytes("new!") forClientMsgID:cid extension:@"bin"]];
    XCTAssertEqualObjects([_store dataForLocalRef:ref], Bytes("new!"));
}

/// 从文件拷贝：源文件保留；移动：源文件没了。覆盖旧残留（copyItem 遇到已存在会失败，所以必须先删）。
- (void)test_拷贝保留源文件_移动不保留_且覆盖旧残留 {
    NSString *src = [NSTemporaryDirectory() stringByAppendingPathComponent:[self cid]];
    [Bytes("filebytes") writeToFile:src atomically:YES];
    NSString *cid = [self cid];
    NSString *ref = [self track:[_store storeFileAtURL:[NSURL fileURLWithPath:src] forClientMsgID:cid extension:@"mov"]];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:src], @"拷贝不能动源文件");
    XCTAssertEqualObjects([_store dataForLocalRef:ref], Bytes("filebytes"));
    // 再来一次同键：覆盖。
    [Bytes("v2") writeToFile:src atomically:YES];
    NSString *ref2 = [self track:[_store storeFileAtURL:[NSURL fileURLWithPath:src] forClientMsgID:cid extension:@"mov"]];
    XCTAssertEqualObjects([_store dataForLocalRef:ref2], Bytes("v2"));
    // 移动：源没了。
    NSString *src2 = [NSTemporaryDirectory() stringByAppendingPathComponent:[self cid]];
    [Bytes("moved") writeToFile:src2 atomically:YES];
    NSString *ref3 = [self track:[_store storeByMovingFileAtURL:[NSURL fileURLWithPath:src2] forClientMsgID:[self cid] extension:@"mov"]];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:src2], @"移动后源文件应已不在");
    XCTAssertEqualObjects([_store dataForLocalRef:ref3], Bytes("moved"));
    [NSFileManager.defaultManager removeItemAtPath:src error:NULL];
}

#pragma mark - 路径安全

/// 写入侧也必须拒绝含 `/` 或 `..` 的键：否则文件会被写到暂存目录之外，而返回的引用读取侧又会拒绝（读不回来）。
- (void)test_写入侧拒绝路径穿越的键 {
    XCTAssertNil([_store storeData:Bytes("x") forClientMsgID:@"../escape" extension:@"jpg"]);
    XCTAssertNil([_store storeData:Bytes("x") forClientMsgID:@"a/b" extension:@"jpg"]);
    XCTAssertNil([_store storeData:Bytes("x") forClientMsgID:@"ok" extension:@"../x"]);
    NSString *src = [NSTemporaryDirectory() stringByAppendingPathComponent:[self cid]];
    [Bytes("x") writeToFile:src atomically:YES];
    XCTAssertNil([_store storeFileAtURL:[NSURL fileURLWithPath:src] forClientMsgID:@"../escape" extension:nil]);
    XCTAssertNil([_store storeByMovingFileAtURL:[NSURL fileURLWithPath:src] forClientMsgID:@"x/y" extension:nil]);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:src], @"被拒绝时源文件不能被动过");
    [NSFileManager.defaultManager removeItemAtPath:src error:NULL];
}

/// 读取侧：穿越型 / 非本地标识 / 不存在的文件，一律 nil。
- (void)test_读取侧拒绝穿越与不存在 {
    // 在暂存目录的**上一级**真造一个文件，再用 `../` 指它：不拒绝的话这里会读到它（光指向不存在的路径是空转）。
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *outsideName = [@"pm-outside-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *outside = [base stringByAppendingPathComponent:outsideName];
    [Bytes("secret") writeToFile:outside atomically:YES];
    XCTAssertNil([_store filePathForLocalRef:[@"im-pending://../" stringByAppendingString:outsideName]]);
    XCTAssertNil([_store dataForLocalRef:[@"im-pending://../" stringByAppendingString:outsideName]]);
    [NSFileManager.defaultManager removeItemAtPath:outside error:NULL];
    XCTAssertNil([_store filePathForLocalRef:@"im-pending://../etc/passwd"]);
    XCTAssertNil([_store filePathForLocalRef:@"im-pending://a/b"]);
    XCTAssertNil([_store filePathForLocalRef:@"https://x/y"]);
    XCTAssertNil([_store filePathForLocalRef:nil]);
    XCTAssertNil([_store filePathForLocalRef:@"im-pending://definitely-not-there.jpg"]);
    XCTAssertNil([_store dataForLocalRef:@"im-pending://definitely-not-there.jpg"]);
    XCTAssertEqual([_store byteSizeForLocalRef:@"im-pending://definitely-not-there.jpg"], 0);
}

#pragma mark - upload_id 旁挂

/// 旁挂 upload_id：写入后能读回（杀进程重启仍可续传）；传空串清除；不存在的引用安静无操作。
- (void)test_uploadID旁挂读写与清除 {
    NSString *ref = [self track:[_store storeData:Bytes("x") forClientMsgID:[self cid] extension:@"mp4"]];
    XCTAssertNil([_store uploadIDForLocalRef:ref]);
    [_store setUploadID:@"up-123" forLocalRef:ref];
    XCTAssertEqualObjects([_store uploadIDForLocalRef:ref], @"up-123");
    [_store setUploadID:@"" forLocalRef:ref];
    XCTAssertNil([_store uploadIDForLocalRef:ref]);
    [_store setUploadID:@"up" forLocalRef:@"im-pending://nope.mp4"]; // 不崩
    XCTAssertNil([_store uploadIDForLocalRef:@"im-pending://nope.mp4"]);
}

/// 清理：主文件与旁挂文件**一起**删（必须先取旁挂路径，删了主文件就找不到路径了）。
- (void)test_清理同时删主文件与旁挂 {
    NSString *ref = [_store storeData:Bytes("x") forClientMsgID:[self cid] extension:@"mp4"];
    [_store setUploadID:@"up-1" forLocalRef:ref];
    NSString *path = [_store filePathForLocalRef:ref];
    NSString *sidecar = [path stringByAppendingPathExtension:@"uploadid"];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:sidecar]);
    [_store removeLocalRef:ref];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:path]);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:sidecar], @"旁挂文件不能残留");
    XCTAssertNil([_store filePathForLocalRef:ref]);
}

@end
