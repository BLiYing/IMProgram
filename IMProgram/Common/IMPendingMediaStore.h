//  IMPendingMediaStore.h
//  待发媒体的本地暂存。
//
//  背景：发送失败的图片/视频原先只活在内存里——乐观气泡不落库、原始字节随 IMPickedMediaHandle 释放，
//  退出会话再进来就彻底消失，也无从重试。这里把**已就绪待上传的字节**按 client_msg_id 落到
//  Application Support（不是 Caches，系统不会在空间紧张时清掉），消息则以本地路径落库：
//    - 重进会话能看到失败气泡，且缩略图直接读本地文件，不走网络；
//    - 点击可重试，杀进程重启也能重试；
//    - 发送成功即删除本地副本，避免长期占用空间。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地待发文件的 URL 前缀。消息 content 以此开头 = 尚未上传成功的本地文件。
extern NSString * const kIMPendingMediaScheme;

@interface IMPendingMediaStore : NSObject

+ (instancetype)shared;

/// 落盘待发字节，返回可存进消息 content 的本地标识（`im-pending://<clientMsgID>.<ext>`）；失败返回 nil。
- (nullable NSString *)storeData:(NSData *)data
                  forClientMsgID:(NSString *)clientMsgID
                       extension:(nullable NSString *)extension;

/// 同上，但**从文件系统拷贝**而非先读进内存——大文件（几百 MB）绝不能整包进 NSData。
- (nullable NSString *)storeFileAtURL:(NSURL *)fileURL
                       forClientMsgID:(NSString *)clientMsgID
                            extension:(nullable NSString *)extension;

/// 同上，但**移动**源文件（源是我们自己的临时文件时免一次 2GB 级拷贝）；跨卷自动回落 copy+删源。
- (nullable NSString *)storeByMovingFileAtURL:(NSURL *)fileURL
                               forClientMsgID:(NSString *)clientMsgID
                                    extension:(nullable NSString *)extension;

/// 待发文件的字节数（不读内容）；不存在返回 0。
- (int64_t)byteSizeForLocalRef:(nullable NSString *)localRef;

/// 分片上传的 upload_id 旁挂存储：持久化后杀进程重启仍可从服务端 offset 续传。
- (void)setUploadID:(nullable NSString *)uploadID forLocalRef:(nullable NSString *)localRef;
- (nullable NSString *)uploadIDForLocalRef:(nullable NSString *)localRef;

/// 本地标识 → 真实文件路径；不是本地标识或文件已删返回 nil。
- (nullable NSString *)filePathForLocalRef:(nullable NSString *)localRef;

/// 读回字节用于重试；文件不存在返回 nil（调用方应把该条标记为不可重试）。
- (nullable NSData *)dataForLocalRef:(nullable NSString *)localRef;

/// 发送成功/用户删除后清理。
- (void)removeLocalRef:(nullable NSString *)localRef;

/// 是否本地待发标识。
+ (BOOL)isLocalRef:(nullable NSString *)value;

@end

NS_ASSUME_NONNULL_END
