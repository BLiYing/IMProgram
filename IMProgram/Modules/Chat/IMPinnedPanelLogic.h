//  IMPinnedPanelLogic.h
//  置顶消息底部面板（IMPinnedPanelViewController）的纯逻辑：渲染顺序兜底、日期胶囊插行、
//  长按菜单允许项、权限 → 标题栏副标题 / 底栏、定位图标左右规则。无 UI、无 self，配 IMPinnedMessageTests。
//  设计：IMServer docs/design/PINNED_PANEL_DESIGN.md（§2.2 行规格 / §2.3 行为 / §4.0 兜底顺序）。

#import <Foundation/Foundation.h>

@class IMPinnedMessage;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 长按菜单允许项（与 Web / Android 同 id）：取消置顶 / 复制 / 定位到消息，按此顺序。
FOUNDATION_EXPORT NSString * const IMPinnedMenuActionUnpin;
FOUNDATION_EXPORT NSString * const IMPinnedMenuActionCopy;
FOUNDATION_EXPORT NSString * const IMPinnedMenuActionLocate;

/// 长按菜单项：「取消置顶」仅有权限者；「复制」仅文本（按服务端原 content_type 判，兜底气泡的类型词不可复制）；「定位」恒有。
FOUNDATION_EXPORT NSArray<NSString *> *IMPinnedPanelMenuActionIDs(NSString *_Nullable originalContentType,
                                                                  NSString *_Nullable content,
                                                                  BOOL canUnpin);

/// 权限决定的面板外框：无取消权限 → 无副标题「长按消息可取消置顶」、无底栏「取消所有置顶」。
typedef struct {
    BOOL showsLongPressHint;
    BOOL showsUnpinAll;
} IMPinnedPanelChrome;
FOUNDATION_EXPORT IMPinnedPanelChrome IMPinnedPanelChromeForPermission(BOOL canUnpin);

/// 定位图标在气泡哪侧：**我发的在气泡左侧，别人的在气泡右侧**（均紧挨气泡、底边对齐、间距 8）。
FOUNDATION_EXPORT BOOL IMPinnedLocateIconOnLeadingSide(BOOL mine);

/// 一条置顶 → 渲染用的消息模型。兜底顺序（§4.0）：①本地库已有该 conv_seq 的行 → ②接口带的完整 message →
/// ③类型词纯文本气泡（旧服务端）。本地行已撤回 → 返回 nil（面板不出墓碑行，直接摘除）。
/// 认不出的内容类型（如老的 audio、未来新类型）一律走③，绝不把 URL / JSON 原样铺进气泡。
FOUNDATION_EXPORT IMMessageModel *_Nullable IMPinnedResolveMessage(IMPinnedMessage *item,
                                                                  IMMessageModel *_Nullable localRow,
                                                                  NSString *convID);

/// 面板里的一行：日期胶囊行或消息行。
@interface IMPinnedPanelRow : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *dayHeader;     ///< 非空 = 日期胶囊行
@property (nonatomic, strong, readonly, nullable) IMPinnedMessage *item; ///< 消息行：对应置顶项
@property (nonatomic, strong, readonly, nullable) IMMessageModel *message;
@property (nonatomic, assign, readonly) BOOL mine;
@end

/// 按置顶顺序（pinned_at 降序，服务端已排好）铺行：每条消息前插一个日期胶囊——**仅当日期与上一条消息不同**
/// （首条总有；时间未知不插）。resolve 返回 nil 的项（本地已撤回）整条略过。
/// dayHeaderForMillis：日期文案（宿主传 IMTheme dayHeaderStringFromMillis:），sameDay：同日判定。
FOUNDATION_EXPORT NSArray<IMPinnedPanelRow *> *IMPinnedPanelBuildRows(
    NSArray<IMPinnedMessage *> *items,
    IMMessageModel *_Nullable (^resolve)(IMPinnedMessage *item),
    NSString *_Nullable myUID,
    NSString *_Nullable (^dayHeaderForMillis)(int64_t millis),
    BOOL (^sameDay)(int64_t a, int64_t b));

NS_ASSUME_NONNULL_END
