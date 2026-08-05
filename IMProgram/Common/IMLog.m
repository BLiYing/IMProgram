//  IMLog.m

#import "IMLog.h"

#ifdef DEBUG
#import "IMRemoteLogSink.h"
DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
DDLogLevel ddLogLevel = DDLogLevelInfo;
#endif

NSString * const IMLogTagApp = @"IM.APP";
NSString * const IMLogTagHTTP = @"IM.HTTP";
NSString * const IMLogTagSocket = @"IM.WS";
NSString * const IMLogTagDatabase = @"IM.DB";
NSString * const IMLogTagUI = @"IM.UI";
NSString * const IMLogTagMedia = @"IM.MEDIA";

void IMLogConfigure(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [DDLog addLogger:DDOSLogger.sharedInstance];

        DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
        fileLogger.maximumFileSize = 5 * 1024 * 1024;
        fileLogger.rollingFrequency = 24 * 60 * 60;
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
        [DDLog addLogger:fileLogger];

#ifdef DEBUG
        // 开发期第三个 logger：把日志汇聚到服务器，便于在 Mac 上直接 grep 真机日志。
        // 仅 DEBUG 注册；Release 不含此 logger（sink 会读 IMHTTPService.host，登录后才真正发送）。
        [DDLog addLogger:[IMRemoteLogSink new]];
#endif

        IMLog(@"CocoaLumberjack ready level=%lu file=%@",
              (unsigned long)ddLogLevel,
              fileLogger.currentLogFileInfo.filePath ?: @"-");
    });
}
