//  IMClearAll.h
//  「清除所有对话」的纯逻辑与本机收尾（设计 IMServer/docs/design/CLEAR_ALL_CONVERSATIONS_DESIGN.md §1 §4）。
//  HTTP 在 IMHTTPService+ClearAll；批量落库在 IMDatabase+ClearAll；这里放：回包解析、toast 文案、
//  HTTP 成功后的本机落地编排（库 → 会话行 → 媒体缓存 → 通知 / 角标）。

#import <Foundation/Foundation.h>
#import "IMDatabase+ClearAll.h"

NS_ASSUME_NONNULL_BEGIN

/// `POST /users/me/conversations/clear` 的 data：`cleared` 以服务端为准（toast 用），`items` 供发起端立即清本机。
@interface IMClearAllResult : NSObject
@property (nonatomic, assign, readonly) NSInteger cleared;
@property (nonatomic, copy, readonly) NSArray<IMClearAllItem *> *items;
- (instancetype)initWithCleared:(NSInteger)cleared items:(NSArray<IMClearAllItem *> *)items NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

/// 解析 data={cleared, items:[{conv_id, cleared_at}]}。data 不是对象 → nil（调用方当失败，**不得**据此动本机）。
/// items 里 conv_id 为空 / 类型不对的项丢弃；cleared_at 缺省 / 非法按 0；cleared 缺省取 items.count，负数按 0。
FOUNDATION_EXPORT IMClearAllResult *_Nullable IMClearAllParseResponse(id _Nullable data);

/// 成功 toast：n>0 →「已清除 n 个对话」，n<=0 →「没有可清除的对话」。
FOUNDATION_EXPORT NSString *IMClearAllToastText(NSInteger n);

/// 二次确认弹窗正文（带 N）。
FOUNDATION_EXPORT NSString *IMClearAllConfirmBody(NSInteger n);

@interface IMClearAll : NSObject

/// HTTP 成功后的本机落地（后台线程做库与文件，完成后回主线程调 completion）：
/// ① 单事务对每个 items[] 跑「清除到位点」、会话行移除（`-[IMSocketManager applyClearAllItems:]`）；
/// ② 清本机已下载媒体缓存（`IMSessionTeardown.ownedMediaCacheDirectories` + 「看过」登记，**不含头像**所在的图片缓存）；
/// ③ 取消通知中心里本 App 的通知、角标归 0；④ 广播会话更新，列表 / 红点据本地库重算。
/// completion 的 BOOL = 库落地是否成功；失败时服务端已清、本机未动，随后的 conv_update(delete) 回声会补上。
+ (void)applyResult:(IMClearAllResult *)result completion:(void (^)(BOOL dbApplied))completion;

@end

NS_ASSUME_NONNULL_END
