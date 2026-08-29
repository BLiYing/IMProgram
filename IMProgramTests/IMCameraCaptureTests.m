#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../IMProgram/Common/IMMediaPicker.h"

/// 「拍摄」入口支持录像（相机 picker 配置 + 录制产物句柄）。
///
/// 覆盖的是三个「静默失败」的点，都不是编译器能挡住的：
///   1. picker 没设 mediaTypes → 只能拍照（本次改动前的原状）；
///   2. 本地文件句柄的 _ip 为 nil，loadThumbnail 里给 nil 发消息 **completion 永不回调** → 缩略图永久空白；
///   3. 句柄没走到 loadData 就释放 → 录制原件（可达上百 MB）永久留在 tmp。
@interface IMCameraCaptureTests : XCTestCase
@end

@implementation IMCameraCaptureTests

#pragma mark 相机 picker 配置

- (void)testCameraPickerEnablesVideoModeWithDurationCap {
    // 不碰 sourceType：模拟器上设成 Camera 会抛异常，而配置口径与相机是否存在无关。
    UIImagePickerController *picker = [UIImagePickerController new];
    [IMMediaPicker configureCameraPicker:picker];

    XCTAssertTrue([picker.mediaTypes containsObject:UTTypeMovie.identifier], @"没开 movie 就只能拍照");
    XCTAssertTrue([picker.mediaTypes containsObject:UTTypeImage.identifier], @"拍照不能因为加了录像而丢掉");
    XCTAssertEqualWithAccuracy(picker.videoMaximumDuration, kIMCameraVideoMaxSeconds, 0.001);
    XCTAssertEqual(picker.videoQuality, UIImagePickerControllerQualityTypeHigh,
                   @"IFrame 预设是全 I 帧、体积反而更大，分辨率交给转码预设");
}

- (void)testCameraVideoDurationCapStaysWithinTranscodeBudget {
    XCTAssertEqualWithAccuracy(kIMCameraVideoMaxSeconds, 60, 0.001);
    // 上限一旦被调大，先回头看 exportVideoAtURL: 那个写死的 120s 超时：超时会回落发原编码
    // （设备开「高效」格式时收端 Web 播不了），不是简单的"文件大一点"。
    XCTAssertLessThanOrEqual(kIMCameraVideoMaxSeconds, 120);
}

- (void)testConfigureCameraPickerToleratesNil {
    XCTAssertNoThrow([IMMediaPicker configureCameraPicker:nil]);
}

#pragma mark 录制产物句柄

- (void)testHandleRejectsMissingOrEmptyFile {
    XCTAssertNil([IMMediaPicker handleForRecordedVideoAtURL:nil]);
    NSURL *ghost = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"im-no-such.mov"]];
    XCTAssertNil([IMMediaPicker handleForRecordedVideoAtURL:ghost], @"文件不存在要返回 nil，别造一条发不出去的空气泡");

    NSURL *empty = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                           [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"mov"]]];
    XCTAssertTrue([[NSData data] writeToURL:empty atomically:YES]);
    XCTAssertNil([IMMediaPicker handleForRecordedVideoAtURL:empty], @"0 字节同样按失败处理");
    [[NSFileManager defaultManager] removeItemAtURL:empty error:NULL];
}

- (void)testHandleLoadsVideoMetaFromRecordedFile {
    NSURL *source = [self makeTestMovieWithFrames:15]; // 0.5s @30fps
    if (!source) { XCTSkip(@"当前环境无法用 AVAssetWriter 生成测试视频（模拟器编码器不可用）"); }

    IMPickedMediaHandle *handle = [IMMediaPicker handleForRecordedVideoAtURL:source];
    XCTAssertNotNil(handle);
    XCTAssertTrue(handle.isVideo);
    XCTAssertEqualObjects([handle suggestedFileName].pathExtension, @"mov", @"名字要按暂存文件的扩展名来");

    XCTestExpectation *done = [self expectationWithDescription:@"loadData"];
    __block IMPickedMedia *item = nil;
    [handle loadData:^(IMPickedMedia *loaded) {
        item = loaded;
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:120 handler:nil]; // 含一次转码，给足余量

    XCTAssertNotNil(item, @"转码失败也应回落原件，不该整条为 nil");
    XCTAssertTrue(item.isVideo);
    XCTAssertGreaterThan(item.byteCount, 0);
    XCTAssertGreaterThan(item.durationMillis, 0, @"时长要量出来，收端封面角标靠它");
    XCTAssertGreaterThan(item.pixelSize.width, 0, @"宽高要量出来，收端按原比例排版靠它");
    XCTAssertGreaterThan(item.pixelSize.height, 0);
    XCTAssertNotNil(item.fileURL, @"视频产物必须留在磁盘（2GB 上限下绝不能进内存）");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:item.fileURL.path]);

    [[NSFileManager defaultManager] removeItemAtURL:item.fileURL error:NULL];
}

- (void)testLocalHandleThumbnailAlwaysCallsBack {
    NSURL *source = [self makeTestMovieWithFrames:15];
    if (!source) { XCTSkip(@"当前环境无法用 AVAssetWriter 生成测试视频（模拟器编码器不可用）"); }

    IMPickedMediaHandle *handle = [IMMediaPicker handleForRecordedVideoAtURL:source];
    XCTestExpectation *done = [self expectationWithDescription:@"thumbnail"];
    // 回归点：本地句柄没有 NSItemProvider，若还走 loadPreviewImageWithOptions: 这个 block 永远不会被调用。
    [handle loadThumbnail:^(UIImage *thumb) { [done fulfill]; }];
    [self waitForExpectationsWithTimeout:60 handler:nil];

    [[NSFileManager defaultManager] removeItemAtURL:source error:NULL];
}

- (void)testUnconsumedHandleDeletesRecordedFileOnDealloc {
    NSURL *source = [self makeTestMovieWithFrames:5];
    if (!source) { XCTSkip(@"当前环境无法用 AVAssetWriter 生成测试视频（模拟器编码器不可用）"); }

    @autoreleasepool {
        IMPickedMediaHandle *handle = [IMMediaPicker handleForRecordedVideoAtURL:source];
        XCTAssertNotNil(handle);
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:source.path]);
    }
    // 用户在转码开始前就取消了那条乐观气泡：录制原件（真机上可达上百 MB）不能永久留在 tmp。
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:source.path]);
}

#pragma mark 夹具

/// 造一段极小的真视频（320x240 H.264 .mov，模仿相机产物）。环境不支持编码时返回 nil。
- (NSURL *)makeTestMovieWithFrames:(NSInteger)frameCount {
    const NSInteger kW = 320, kH = 240, kFPS = 30;
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"mov"]]];
    NSError *error = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
    if (!writer) { return nil; }
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                  outputSettings:@{ AVVideoCodecKey: AVVideoCodecTypeH264,
                                                                                    AVVideoWidthKey: @(kW),
                                                                                    AVVideoHeightKey: @(kH) }];
    input.expectsMediaDataInRealTime = NO;
    if (![writer canAddInput:input]) { return nil; }
    [writer addInput:input];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                   sourcePixelBufferAttributes:@{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                                  (id)kCVPixelBufferWidthKey: @(kW),
                                                                  (id)kCVPixelBufferHeightKey: @(kH) }];
    if (![writer startWriting]) { return nil; }
    [writer startSessionAtSourceTime:kCMTimeZero];

    for (NSInteger i = 0; i < frameCount; i++) {
        NSInteger spins = 0;
        while (!input.isReadyForMoreMediaData && spins++ < 500) { [NSThread sleepForTimeInterval:0.01]; }
        CVPixelBufferRef pb = NULL;
        if (!adaptor.pixelBufferPool ||
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pb) != kCVReturnSuccess) {
            [writer cancelWriting];
            return nil;
        }
        CVPixelBufferLockBaseAddress(pb, 0);
        memset(CVPixelBufferGetBaseAddress(pb), (int)((i * 16) % 256),
               CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb)); // 逐帧变色，避免被压成 0 帧
        CVPixelBufferUnlockBaseAddress(pb, 0);
        BOOL ok = [adaptor appendPixelBuffer:pb withPresentationTime:CMTimeMake(i, (int32_t)kFPS)];
        CVPixelBufferRelease(pb);
        if (!ok) { [writer cancelWriting]; return nil; }
    }
    [input markAsFinished];

    XCTestExpectation *written = [self expectationWithDescription:@"writer"];
    [writer finishWritingWithCompletionHandler:^{ [written fulfill]; }];
    [self waitForExpectations:@[written] timeout:60];
    if (writer.status != AVAssetWriterStatusCompleted) { return nil; }
    return url;
}

@end
