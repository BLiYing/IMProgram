//  IMLog.m

#import "IMLog.h"

#ifdef DEBUG
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

        IMLog(@"CocoaLumberjack ready level=%lu file=%@",
              (unsigned long)ddLogLevel,
              fileLogger.currentLogFileInfo.filePath ?: @"-");
    });
}
