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

/// 控制台格式化器：给 Xcode 控制台每行加「本地时间 + 级别」前缀（tag 已由 IMLogWithTag 写进正文）。
/// 仅挂在 DDOSLogger 上——DDFileLogger 有自带时间戳格式、IMRemoteLogSink 自建 NDJSON(带 epoch ts)，都不受影响。
/// DDLog 在单个 logger 的串行队列上调用本方法，故复用一个 NSDateFormatter 实例是安全的。
@interface IMConsoleLogFormatter : NSObject <DDLogFormatter>
@end

@implementation IMConsoleLogFormatter {
    NSDateFormatter *_df;
}
- (instancetype)init {
    if (self = [super init]) {
        _df = [[NSDateFormatter alloc] init];
        _df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        _df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; // 固定格式，不随系统区域漂移
    }
    return self;
}
- (NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    NSString *level;
    switch (logMessage.flag) {
        case DDLogFlagError:   level = @"E"; break;
        case DDLogFlagWarning: level = @"W"; break;
        case DDLogFlagInfo:    level = @"I"; break;
        case DDLogFlagDebug:   level = @"D"; break;
        default:               level = @"V"; break;
    }
    return [NSString stringWithFormat:@"%@ [%@] %@",
            [_df stringFromDate:logMessage.timestamp], level, logMessage.message];
}
@end

void IMLogConfigure(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DDOSLogger *console = DDOSLogger.sharedInstance;
        console.logFormatter = [IMConsoleLogFormatter new]; // 控制台补上「时间 + 级别」前缀
        [DDLog addLogger:console];

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
