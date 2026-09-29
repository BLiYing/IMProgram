//  IMCallHistoryRecord.h
//  设置 ▸ 最近通话：单条历史记录的数据结构 + 纯函数（未接判定 / 群通话人数 / 按日期分组 / 全部-未接过滤）。
//  字段对齐 im-rtc SDK `fetchCallHistory` 返回体（设计：IMServer docs/design/CALL_HISTORY_DESIGN.md §1）；
//  与聊天气泡通话记录（`IMCallRecord`）是同一批通话事实的另一种呈现，身份解析 / reason 文案渲染直接
//  复用 `IMCallRecord`（把本记录的字段拼回 `{"cid","m","r","d"[,"g"]}` 再走 `IMCallRecordRender`），
//  本文件只放聊天记录消息没有的东西：未接判定（需要 caller/自己 uid）、群通话人数、按日期分组、筛选。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一条服务端权威通话记录（`GET /v1/calls` 的单条）。纯数据，不含渲染逻辑。
@interface IMCallHistoryRecord : NSObject
@property (nonatomic, copy) NSString *callID;         ///< call_id
@property (nonatomic, copy) NSString *roomID;          ///< room_id（v1 未用到，原样保留供将来诊断）
@property (nonatomic, copy) NSString *caller;          ///< 主叫 uid
@property (nonatomic, assign) BOOL video;              ///< media_type == video
@property (nonatomic, assign) BOOL group;              ///< is_group
@property (nonatomic, copy) NSString *reason;          ///< 协议 reason（表外值由 IMCallRecordRender 折成 error）
@property (nonatomic, copy, nullable) NSString *endedBy; ///< 结束者 uid，可空
@property (nonatomic, assign) NSInteger durationSec;   ///< 服务端给的秒数（未接通恒 0）
@property (nonatomic, assign) int64_t startedAtMs;
@property (nonatomic, assign) int64_t connectedAtMs;
@property (nonatomic, assign) int64_t endedAtMs;
@property (nonatomic, copy, nullable) NSString *userData;
@property (nonatomic, copy, nullable) NSString *chatGroupID; ///< 群通话时宿主自己的群号
@property (nonatomic, copy) NSArray<NSString *> *memberUIDs; ///< 群通话参与者 uid（不含 state，v1 用不到）
@end

/// 「全部 / 未接」筛选（v1 范围，纯端上过滤，设计文档 §3.5）。
typedef NS_ENUM(NSInteger, IMCallHistoryFilter) {
    IMCallHistoryFilterAll = 0,
    IMCallHistoryFilterMissed = 1,
};

/// 未接判定：我是被叫（`caller != selfUID`）且 `durationSec == 0`。
/// `selfUID` 为空（异常态，理论不该发生）时保守返回 NO——宁可不误报未接，也不要在拿不到自己 uid 时把全部记录染红。
FOUNDATION_EXPORT BOOL IMCallHistoryRecordIsMissed(IMCallHistoryRecord *record, NSString *_Nullable selfUID);

/// 单聊对方 uid：`caller != selfUID` 时对方就是 `caller`；否则（我是主叫）从 `memberUIDs` 里找第一个
/// 不是自己的 uid。拿不到（脏数据：caller 为空且 members 里也找不到）返回 nil，调用方走「未命名用户」
/// 兜底，不崩溃、不显示空字符串（设计文档 §6 测试点 3）。仅用于 1v1 记录；群通话不调用本函数。
FOUNDATION_EXPORT NSString *_Nullable IMCallHistoryRecordPeerUID(IMCallHistoryRecord *_Nullable record, NSString *_Nullable selfUID);

/// 群通话对方人数：`max(members.length, 1) + (caller 是否已在 members 里 ? 0 : 1)`
/// （对齐 im-rtc Demo `peerText` 逻辑，见设计文档 §1；与是否把发起人算进 `members` 无关，结果都一致）。
FOUNDATION_EXPORT NSInteger IMCallHistoryGroupPeerCount(NSArray<NSString *> *memberUIDs, NSString *_Nullable callerUID);

/// 按 `IMCallHistoryFilter` 过滤（不改变顺序，不做翻页决策——翻页策略在 IMCallHistoryPaginator）。
FOUNDATION_EXPORT NSArray<IMCallHistoryRecord *> *IMCallHistoryApplyFilter(NSArray<IMCallHistoryRecord *> *records,
                                                                            IMCallHistoryFilter filter,
                                                                            NSString *_Nullable selfUID);

/// 一个日期分组（今天 / 昨天 / 具体日期）。
@interface IMCallHistorySection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<IMCallHistoryRecord *> *records;
@end

/// 按 `startedAtMs` 自然日分组；假定 `records` 已按时间倒序（SDK 保证），不重新排序。
/// 分组标题复用 `IMTheme dayHeaderStringFromMillis:`（与聊天页日期分隔胶囊同一套计算，不新造一套）。
FOUNDATION_EXPORT NSArray<IMCallHistorySection *> *IMCallHistoryGroupByDate(NSArray<IMCallHistoryRecord *> *sortedDescRecords);

NS_ASSUME_NONNULL_END
