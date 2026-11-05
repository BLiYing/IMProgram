//  IMShareSelection.h
//  分享选择页的**选中集**（纯逻辑、无 UIKit、可单测）。设计稿 IMServer/docs/design/sketches/SHARE_PICKER_UX_SKETCH.html ⑦。
//
//  一份实例由「最近聊天」主页、「我的好友」「我的群聊」两个子页共用：
//  · **唯一键 = conv_id**。好友按协议规则在本地推导 `u_a_u_b`（IMConversationID），群直接用 g_xxx——
//    同一个人 / 群不管从哪张表勾的都是同一项，所以在最近聊天勾了张三、进好友页张三就是已勾选。
//  · 存的是 IMConversation（好友 / 群没会话时临时合成一个），调用方 onDone 只用 convID / isGroup / peer，
//    故 7 个分享入口无需改动就能发到「没聊过的好友」「删过会话的群」。
//  · 上限是**合计**（三处一起算），三端同值 9（iOS kIMForwardMaxSelection / Web MAX_FORWARD_TARGETS）。
//  三端同口径：im-web `src/shareTargets.ts`、im-android `data/SharePick.kt`。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;
@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMShareToggleResult) {
    IMShareToggleAdded,
    IMShareToggleRemoved,
    IMShareToggleCapped,    ///< 已满，未加入（调用方吐司「最多选择 N 个会话」）
    IMShareToggleInvalid,   ///< conv_id 为空，忽略
};

@interface IMShareSelection : NSObject

- (instancetype)initWithLimit:(NSUInteger)limit NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSUInteger limit;
@property (nonatomic, readonly) NSUInteger count;
/// 按勾选顺序。
@property (nonatomic, readonly) NSArray<IMConversation *> *conversations;

- (BOOL)containsConvID:(nullable NSString *)convID;
- (IMShareToggleResult)toggle:(IMConversation *)conversation;
/// 返回是否真的删掉了。
- (BOOL)removeConvID:(NSString *)convID;
- (void)clear;

/// 好友 → 会话目标（convID 本地推导；名字 / 头像带上，供已选栏与确认面板显示）。selfUID 为空返回 nil。
+ (nullable IMConversation *)conversationForFriend:(IMUserCard *)card selfUID:(nullable NSString *)selfUID;
/// 群 → 会话目标。convID 为空返回 nil。
+ (nullable IMConversation *)conversationForGroup:(IMGroupInfo *)group;

/// 好友是否可作分享目标：已注销 / 已拉黑 / 系统通知号都不行（发了也会被服务端拒或无意义）。
+ (BOOL)isShareableFriend:(IMUserCard *)card;

/// 从 candidates 里剔除 conv_id 落在 excluded 里的项（保持顺序）。主页搜索用：
/// 已出现在「最近聊天」的人 / 群不在「好友」「群聊」分组里重复出现。
+ (NSArray<IMConversation *> *)conversations:(NSArray<IMConversation *> *)candidates
                           excludingConvIDs:(NSSet<NSString *> *)excluded;

@end

NS_ASSUME_NONNULL_END
