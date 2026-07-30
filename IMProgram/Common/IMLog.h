//  IMLog.h
//  CocoaLumberjack 统一日志入口。业务代码禁止直接调用 NSLog/DDLog*。

#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT DDLogLevel ddLogLevel;

FOUNDATION_EXPORT NSString * const IMLogTagApp;
FOUNDATION_EXPORT NSString * const IMLogTagHTTP;
FOUNDATION_EXPORT NSString * const IMLogTagSocket;
FOUNDATION_EXPORT NSString * const IMLogTagDatabase;
FOUNDATION_EXPORT NSString * const IMLogTagUI;

/// App 启动时调用一次：注册系统控制台与滚动文件 Logger。
FOUNDATION_EXPORT void IMLogConfigure(void);

#define IMLogWithTag(tag, fmt, ...) \
    DDLogInfo((@"[%@] " fmt), (tag), ##__VA_ARGS__)

#define IMLogDebugWithTag(tag, fmt, ...) \
    DDLogDebug((@"[%@] " fmt), (tag), ##__VA_ARGS__)

#define IMLogWarnWithTag(tag, fmt, ...) \
    DDLogWarn((@"[%@] " fmt), (tag), ##__VA_ARGS__)

#define IMLogErrorWithTag(tag, fmt, ...) \
    DDLogError((@"[%@] " fmt), (tag), ##__VA_ARGS__)

// 兼容现有调用；新代码优先选明确模块宏。
#define IMLog(fmt, ...) IMLogWithTag(IMLogTagApp, fmt, ##__VA_ARGS__)
#define IMLogHTTP(fmt, ...) IMLogWithTag(IMLogTagHTTP, fmt, ##__VA_ARGS__)
#define IMLogSocket(fmt, ...) IMLogWithTag(IMLogTagSocket, fmt, ##__VA_ARGS__)
#define IMLogDatabase(fmt, ...) IMLogWithTag(IMLogTagDatabase, fmt, ##__VA_ARGS__)
#define IMLogUI(fmt, ...) IMLogWithTag(IMLogTagUI, fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
