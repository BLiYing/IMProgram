//  IMCallRecord.h
//  音视频通话记录消息（content_type=call）的 content 解析 / 构造 / 渲染（纯逻辑，可单测）。
//  content 是极小 JSON：{"cid","m","r","d"[,"g":1]}——call_id / audio|video / 协议 §6 reason / 服务端给的秒数 / 群通话标记。
//  设计：IMServer docs/design/CALL_RECORD_DESIGN.md；文案矩阵以 docs/conformance/call_record.json 为准（三端 + 服务端共用向量，改文案先改向量）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// call 消息的 content_type 常量（与后端 store.ContentTypeCall 一致）。
FOUNDATION_EXPORT NSString * const IMContentTypeCall;

/// 旧版兜底文案：content 解析不了（脏数据 / 将来的新版本字段）时，气泡位显一行灰字，绝不露 JSON。
FOUNDATION_EXPORT NSString * const IMCallRecordUnsupportedText;

typedef NS_ENUM(NSInteger, IMCallRecordTone) {
    IMCallRecordToneNormal = 0,
    IMCallRecordToneMissed,   ///< 被叫侧未接来电：红字，计未读
};

/// 解析后的记录。
@interface IMCallRecord : NSObject
@property (nonatomic, copy) NSString *callID;       ///< cid
@property (nonatomic, assign) BOOL video;           ///< m == video
@property (nonatomic, copy) NSString *reason;       ///< r，原样（表外值由渲染折成 error）
@property (nonatomic, assign) NSInteger durationSec;///< d，服务端给的秒数（≥0）
@property (nonatomic, assign) BOOL group;           ///< g == 1
@end

/// 渲染结果（同一条消息按「看的人」出两套）。
@interface IMCallRecordDisplay : NSObject
@property (nonatomic, copy) NSString *text;         ///< 气泡 / 系统条正文
@property (nonatomic, assign) IMCallRecordTone tone;
@property (nonatomic, assign) BOOL tappable;        ///< 单聊记录可点回拨；群系统条 / 兜底不可点
@property (nonatomic, copy) NSString *preview;      ///< 会话列表预览：`[语音通话] <气泡同句>` / `[群视频通话] 时长 12:03`
@property (nonatomic, assign) BOOL video;           ///< 图标：电话 / 摄像机
@property (nonatomic, assign) BOOL supported;       ///< NO = 解析失败，走兜底
@end

/// 解析 content；非法 JSON / cid 空 / m 不是 audio|video → nil（调用方走兜底，不可点、不露 JSON）。
FOUNDATION_EXPORT IMCallRecord *_Nullable IMCallRecordParse(NSString *_Nullable content);

/// 构造 content（发送用）。cid 空返回 nil；d<0 归 0；group=YES 多写 "g":1。
FOUNDATION_EXPORT NSString *_Nullable IMCallRecordBuild(NSString *_Nullable callID, BOOL video,
                                                        NSString *_Nullable reason, NSInteger durationSec, BOOL group);

/// 时长格式：<1h → mm:ss；≥1h → h:mm:ss。
FOUNDATION_EXPORT NSString *IMCallRecordFormatDuration(NSInteger sec);

/// 渲染。senderName 只用于群系统条（发起人名，本人传任意值——viewerIsSender=YES 时写「你」）。
/// 判定顺序：d>0 →「通话时长 mm:ss」；否则按 r 查表；表外 →「通话未接通」。
FOUNDATION_EXPORT IMCallRecordDisplay *IMCallRecordRender(NSString *_Nullable content, BOOL viewerIsSender,
                                                          BOOL isGroup, NSString *_Nullable senderName);

/// 会话列表 / 置顶横幅 / 引用 / 合并转发条目用的预览。未解析时回落 `[音视频通话]`。
FOUNDATION_EXPORT NSString *IMCallRecordPreview(NSString *_Nullable content, BOOL viewerIsSender, BOOL isGroup);

/// 与视角无关的预览（引用快照 / 收藏 / 合并转发这类没有「我」的位置）：固定 `[音视频通话]`。
FOUNDATION_EXPORT NSString *IMCallRecordNeutralPreview(void);

NS_ASSUME_NONNULL_END
