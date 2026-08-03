//  IMMediaSendService.h
//  常驻媒体发送队列：**转码 → 落盘 → 上传 → 发消息**全链路活在这里，不随聊天页销毁。
//
//  背景：原先整条链路的回调都锚在 IMChatViewController（__weak self），页面一销毁链路即断——
//    - 转码期间退出：字节尚未落盘、消息尚未落库 → 重进会话这条彻底消失；
//    - 上传完成时无聊天页存活：completionHandler no-op → 消息永远发不出去，状态卡在 sending。
//  现在聊天页只做三件事：创建乐观消息 → enqueue → 监听通知渲染进度/结果。
//  进度与预览图字典也归本服务持有（key=clientMsgID 全局唯一），页面重建后直接引用即可接上状态。
//
//  线程约定：对外状态（progressMap/previews/作业表）只在**主线程**读写；磁盘 IO 内部走串行队列。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMPickedMediaHandle, IMMessageModel, IMUploadProgress, IMDatabaseAccountContext;

/// 进度/阶段变化（转码百分比、上传字节、暂停态翻转）。userInfo: conv_id, client_msg_id。
extern NSNotificationName const IMMediaSendProgressDidChangeNotification;
/// 媒体元数据就绪（宽高/时长/字节数已量出、消息已按 im-pending:// 落库）。
/// 气泡此时应从方形占位切到真实比例。userInfo: conv_id, client_msg_id。
extern NSNotificationName const IMMediaSendMetaDidChangeNotification;
/// 上传完成、消息已经 socket 发出，clientMsgID 已从临时键换成真实 ID（库里已 replace + upsert）。
/// userInfo: conv_id, old_client_msg_id, client_msg_id。持有旧模型的页面要同步换 ID/URL（见 message 参数）。
extern NSNotificationName const IMMediaSendDidDispatchNotification;
/// 作业失败（消息已以 failed 状态落库，可点击重试）。userInfo: conv_id, client_msg_id。
extern NSNotificationName const IMMediaSendDidFailNotification;
/// 用户取消发送（本地副本与消息行已删除，页面应移除该行）。userInfo: conv_id, client_msg_id。
extern NSNotificationName const IMMediaSendDidCancelNotification;
/// 服务端 ack 结果（状态/conv_seq/被拒 note 已落库）。userInfo: conv_id, client_msg_id, success(NSNumber),
/// conv_seq(NSNumber)。
extern NSNotificationName const IMMediaSendAckNotification;

extern NSString * const kIMMediaSendConvIDKey;
extern NSString * const kIMMediaSendClientMsgIDKey;
extern NSString * const kIMMediaSendOldClientMsgIDKey;
extern NSString * const kIMMediaSendSuccessKey;
extern NSString * const kIMMediaSendConvSeqKey;
/// DidDispatch / Ack 通知 userInfo 里的消息模型（服务持有的实例；页面若持有同 clientMsgID 的
/// **另一个**实例——如重进会话后从库里读的——据此把字段同步过去）。
extern NSString * const kIMMediaSendMessageKey;

@interface IMMediaSendService : NSObject

+ (instancetype)shared;

/// 待发预览图（key=clientMsgID；转正式发送后键随之迁移）。主线程读写。
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, UIImage *> *previews;
/// 各作业进度（key=clientMsgID）。主线程读写；页面手工标记（如失败清理）也写这里。
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, IMUploadProgress *> *progressMap;

/// 会话内仍在服务里跑、**尚未落库**的乐观消息（转码/落盘尚未完成的那一小段窗口）。
/// 重进会话时把它们合并进列表，否则这条消息要等落库后才可见。返回服务持有的模型实例。
- (NSArray<IMMessageModel *> *)inFlightMessagesInConv:(NSString *)convID;

/// 该 clientMsgID 是否有活跃作业（排队/转码/上传中；不含已 dispatch）。
- (BOOL)hasActiveJobForClientMsgID:(NSString *)clientMsgID;

/// 会话内是否有**本次运行中**失败、尚未重试/取消的发送件（会话列表显红色感叹号用）。
/// 不含 App 重启前遗留的失败行（那些行进会话即见，列表不另行标注）。
- (BOOL)hasFailedOutboxInConv:(NSString *)convID;

/// 相册媒体（图片/视频）批量入列：句柄逐项串行 loadData（转码带进度）→ 字节落盘+落库 →
/// 上传（≥分片阈值走分片、可续传）→ 视频补传封面 → socket 发消息。
/// messages 与 handles 一一对应（调用方已创建乐观模型并上屏）；缩略图也由服务加载并写入 previews。
- (void)enqueueMediaHandles:(NSArray<IMPickedMediaHandle *> *)handles
                   messages:(NSArray<IMMessageModel *> *)messages
                     toUser:(NSString *)toUser
                  dbContext:(nullable IMDatabaseAccountContext *)dbContext;

/// 大文件消息入列（调用方已 storeFileAtURL 落盘、消息已落库）：分片上传 → socket 发文件消息。
/// 同 clientMsgID 已有任务时幂等（不重复上传）。
- (void)enqueueFileMessage:(IMMessageModel *)m
                    toUser:(NSString *)toUser
                 dbContext:(nullable IMDatabaseAccountContext *)dbContext;

/// 重试一条已落库的待发消息（content 为 im-pending:// 本地引用；image/video/file 通吃）。
/// 分片作业读旁挂 upload_id 从服务端 offset 续传（杀进程后的孤儿 sending 行也走这里自动认领）；
/// 返回 NO=本地副本已丢失，无法重试。
- (BOOL)retryMessage:(IMMessageModel *)m
              toUser:(NSString *)toUser
           dbContext:(nullable IMDatabaseAccountContext *)dbContext;

/// 暂停 ↔ 继续（仅分片作业可暂停；恢复时以服务端 offset 为准续传）。
/// 返回 NO=该消息当前没有可暂停的上传任务（如一次性小上传/转码期）。
- (BOOL)togglePauseForMessage:(IMMessageModel *)m;

/// 取消发送：停止上传/丢弃转码产物、删除本地待发副本与消息行，发 DidCancel 通知。
/// 转码本身无法中途打断（AVAssetExportSession 只支持 cancel 整单），产物就绪后会被直接丢弃。
- (void)cancelMessage:(IMMessageModel *)m dbContext:(nullable IMDatabaseAccountContext *)dbContext;

@end

NS_ASSUME_NONNULL_END
