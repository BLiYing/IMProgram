//  IMRemoteLogSink.h
//  开发期日志汇聚（DEBUG only）：把 CocoaLumberjack 日志攒批 POST 到服务器 /__devlog，
//  服务端追加到 dev-logs/im-ios.log，便于在 Mac 上直接 grep 真机日志。
//
//  为什么需要它：真机日志写在 App 沙盒文件里，无线调试连接下 idevicesyslog/devicectl 都不稳；
//  网络汇聚只依赖"设备能连到服务器"（App 本就一直在连），且是「客户端日志上传」正式功能的地基。
//
//  设计约束：
//   - **仅 DEBUG**：Release 构建不注册（见 IMLogConfigure）。
//   - **绝不阻塞、绝不崩**：独立串行队列攒批，独立裸 NSURLSession 发送，失败即丢。
//   - **不自我循环**：内部一律不走 DDLog/IMLog，也不经 IMHTTPService（那会为每次上报再生成一条日志）。
//   - **有界**：缓冲上限固定，服务器不可达时丢最旧的，内存不涨。
//   - **惰性取 host**：启动时 host 未知（登录后才有），flush 时才读 IMHTTPService.host，空则继续攒。

#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMRemoteLogSink : DDAbstractLogger
@end

NS_ASSUME_NONNULL_END
