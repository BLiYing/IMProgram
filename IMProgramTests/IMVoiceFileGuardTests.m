//  IMVoiceFileGuardTests.m
//  `IMVoiceFileIsPlayable` 的护栏：它挡的是一类**会让整个 App 当场消失**的崩溃——
//  `AVAudioPlayer` 用「总帧数 ÷ 每包帧数」算时长与位点，遇到 framesPerPacket == 0 的流会在
//  AVFAudio 内部除零（EXC_ARITHMETIC / SIGFPE，`@try` 拦不住）。2026-08-30 由 Chrome 录的
//  MP4/Opus 语音触发：点开合并转发记录里的那条语音，App 直接退出。
//  这里用真文件跑：合成一段合法 WAV（LPCM，framesPerPacket=1）应放行并报出时长；
//  非音频字节应被挡住。

#import <XCTest/XCTest.h>
#import "IMVoicePlayer.h"

@interface IMVoiceFileGuardTests : XCTestCase
@end

@implementation IMVoiceFileGuardTests {
    NSMutableArray<NSURL *> *_temps;
}

- (void)setUp { [super setUp]; _temps = [NSMutableArray array]; }

- (void)tearDown {
    for (NSURL *u in _temps) { [NSFileManager.defaultManager removeItemAtURL:u error:NULL]; }
    [super tearDown];
}

- (NSURL *)writeTempFileNamed:(NSString *)name data:(NSData *)data {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]]];
    [data writeToURL:url atomically:YES];
    [_temps addObject:url];
    return url;
}

/// 合成一段 8kHz / 单声道 / 16bit 的静音 WAV（44 字节标准头 + 静音采样）。
- (NSURL *)writeSilentWAVMillis:(int)millis {
    const uint32_t rate = 8000; const uint16_t ch = 1, bits = 16;
    uint32_t frames = (uint32_t)((uint64_t)rate * (uint64_t)millis / 1000);
    uint32_t dataBytes = frames * ch * (bits / 8);
    NSMutableData *d = [NSMutableData data];
    void (^put32)(uint32_t) = ^(uint32_t v) { [d appendBytes:&v length:4]; };
    void (^put16)(uint16_t) = ^(uint16_t v) { [d appendBytes:&v length:2]; };
    [d appendBytes:"RIFF" length:4]; put32(36 + dataBytes);
    [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4]; put32(16); put16(1); put16(ch); put32(rate);
    put32(rate * ch * (bits / 8)); put16(ch * (bits / 8)); put16(bits);
    [d appendBytes:"data" length:4]; put32(dataBytes);
    [d appendData:[NSMutableData dataWithLength:dataBytes]];
    return [self writeTempFileNamed:@"silence.wav" data:d];
}

- (void)testPlayableWAVPassesAndReportsDuration {
    NSURL *wav = [self writeSilentWAVMillis:500];
    int64_t ms = 0;
    XCTAssertTrue(IMVoiceFileIsPlayable(wav, &ms));
    XCTAssertEqualWithAccuracy((double)ms, 500.0, 40.0, @"时长应从文件头算出（老记录没有 d 字段时靠它补）");
}

- (void)testNonAudioBytesAreRejectedInsteadOfCrashing {
    NSURL *junk = [self writeTempFileNamed:@"junk.m4a"
                                      data:[@"this is definitely not audio" dataUsingEncoding:NSUTF8StringEncoding]];
    int64_t ms = -1;
    XCTAssertFalse(IMVoiceFileIsPlayable(junk, &ms));
    XCTAssertEqual(ms, 0, @"被挡住时时长必须归零，别把上一次的值留给调用方");
}

- (void)testMissingFileAndNonFileURLAreRejected {
    XCTAssertFalse(IMVoiceFileIsPlayable(nil, NULL));
    XCTAssertFalse(IMVoiceFileIsPlayable([NSURL URLWithString:@"https://example.com/a.m4a"], NULL));
    XCTAssertFalse(IMVoiceFileIsPlayable([NSURL fileURLWithPath:@"/tmp/definitely-missing-XYZ.m4a"], NULL));
}

@end
