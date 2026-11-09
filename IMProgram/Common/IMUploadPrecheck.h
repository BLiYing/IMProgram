//  IMUploadPrecheck.h
//  聊天媒体发送前预检（后台「系统设置 ▸ 上传与媒体」S3a）：按 GET /api/v1/server-config 下发的
//  upload_enabled / upload_max_file_bytes / upload_blocked_extensions，在**创建待发消息、起上传之前**拦下
//  服务端注定会拒的发送，免得用户白等一次上传再看到失败。
//
//  判定顺序与服务端 upload_policy.go `check` 一致：总开关（500003）→ 被禁扩展名（500002）→ 超上限（500001）。
//  **语音只看总开关**：扩展名与单文件上限都不作用于语音（服务端语音另有固定 16 MB，不随后台变）。
//  **头像不预检**：/api/v1/avatar 不受上传策略约束。
//  端上的值可能落后一次拉取：服务端仍以当前值为准（complete 时会再查一次），失败照常标失败、按码提示。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMUploadPrecheckResult) {
    IMUploadPrecheckOK = 0,
    IMUploadPrecheckDisabled,     ///< 管理员暂停了聊天文件上传（对应 500003）
    IMUploadPrecheckBlockedType,  ///< 扩展名被禁（对应 500002）
    IMUploadPrecheckTooLarge,     ///< 超单文件上限（对应 500001）
};

/// 纯判定。fileName 取扩展名（大小写不敏感）；byteCount <= 0 = 体积未知（不判大小，留给后续 / 服务端）。
/// maxFileBytes <= 0 视为默认 2 GiB；blockedExtensions 小写带点（如 ".exe"），nil = 无禁止。
FOUNDATION_EXPORT IMUploadPrecheckResult IMUploadPrecheckEvaluate(NSString *_Nullable fileName, long long byteCount,
                                                                  BOOL isVoice, BOOL enabled, long long maxFileBytes,
                                                                  NSArray<NSString *> *_Nullable blockedExtensions);

/// 纯函数：通过返回 nil；否则返回给用户看的本地化提示（err.500003 / upload.precheck.blocked_type /
/// upload.precheck.too_large）。参数同 IMUploadPrecheckEvaluate。
FOUNDATION_EXPORT NSString *_Nullable IMUploadPrecheckMessage(NSString *_Nullable fileName, long long byteCount,
                                                              BOOL isVoice, BOOL enabled, long long maxFileBytes,
                                                              NSArray<NSString *> *_Nullable blockedExtensions);

/// 上限文案：恰为 1 GiB 整数倍 → "N GB"；整 MiB → "N MB"；否则保留一位小数 "1.5 MB"（同服务端 uploadLimitLabel）。
FOUNDATION_EXPORT NSString *IMUploadLimitLabel(long long bytes);

@class IMServerConfigStore;

/// 业务入口：读 IMServerConfigStore.shared 的当前值做预检，拦下时记一条 IM.MEDIA 日志并**触发一次配置重拉**
/// （缓存可能已过期：管理员关了又开时，不重拉就会一直在本地拦、请求到不了服务端）。nil = 放行。
FOUNDATION_EXPORT NSString *_Nullable IMUploadPrecheckCurrent(NSString *_Nullable fileName, long long byteCount, BOOL isVoice);

/// 同上，store 可注入（单测用；业务一律走 IMUploadPrecheckCurrent）。
FOUNDATION_EXPORT NSString *_Nullable IMUploadPrecheckWithStore(IMServerConfigStore *store, NSString *_Nullable fileName,
                                                                long long byteCount, BOOL isVoice);

/// 服务端上传策略拒绝码（500001 超限 / 500002 类型 / 500003 暂停）：确定性业务错误，重试同一文件必然再失败。
FOUNDATION_EXPORT BOOL IMUploadIsPolicyRejectionCode(NSInteger code);

/// 服务端上传策略拒绝 → 本地化文案（纯函数）：服务端 message 是中文原文，英文界面下不能直接透传。
/// 500003 → err.500003；500001 → upload.precheck.too_large（上限取 maxFileBytes）；
/// 500002 → 扩展名在禁用表里才用 upload.precheck.blocked_type，否则（本就不支持的格式）用 serverText。
FOUNDATION_EXPORT NSString *_Nullable IMUploadServerRejectionMessage(NSInteger code, NSString *_Nullable serverText,
                                                                     NSString *_Nullable fileName, long long maxFileBytes,
                                                                     NSArray<NSString *> *_Nullable blockedExtensions);

/// 同上，取 IMServerConfigStore.shared 的当前值，并触发一次配置重拉。
FOUNDATION_EXPORT NSString *_Nullable IMUploadServerRejectionMessageCurrent(NSInteger code, NSString *_Nullable serverText,
                                                                            NSString *_Nullable fileName);


NS_ASSUME_NONNULL_END
