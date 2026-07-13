//  IMChatDetailTabs.h
//  会话详情页「分类页签」的类型推导（纯逻辑，可单测）。
//  仿 Telegram：页签**按会话内实际存在的消息类型动态生成**——只展示存在的类别，
//  文本/系统/撤回/合并转发等不单独成签。群聊额外恒有「成员」签且排第一（非消息类型）。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 一个页签的类别。除 Members 外均由消息类型派生。
typedef NS_ENUM(NSInteger, IMDetailTabKind) {
    IMDetailTabKindMembers = 0, ///< 成员（仅群聊，恒在第一位；不是消息类型）
    IMDetailTabKindMedia,       ///< 媒体（image / video）
    IMDetailTabKindFiles,       ///< 文件（file）
    IMDetailTabKindVoice,       ///< 语音（audio）
    IMDetailTabKindLinks,       ///< 链接（文本消息且形如 URL，或 link 类型）
};

/// 页签描述：类别 + 展示标题。
@interface IMChatDetailTab : NSObject
@property (nonatomic, assign) IMDetailTabKind kind;
@property (nonatomic, copy) NSString *title;
@end

@interface IMChatDetailTabs : NSObject

/// 由消息列表推导有序页签：群聊「成员」恒第一；其余按 媒体→文件→语音→链接 顺序，仅当该类别存在消息时才出现。
/// messages 为空的群聊也会有「成员」。单聊无「成员」，若无任何可归类消息则返回空数组（调用方隐藏页签区）。
+ (NSArray<IMChatDetailTab *> *)tabsForMessages:(nullable NSArray<IMMessageModel *> *)messages
                                        isGroup:(BOOL)isGroup;

/// 某条消息是否属于某内容页签类别（Members 恒 NO）。用于页签内容过滤，避免与推导逻辑重复。
/// 撤回消息、空内容一律不计入任何类别。
+ (BOOL)message:(nullable IMMessageModel *)message matchesKind:(IMDetailTabKind)kind;

@end

NS_ASSUME_NONNULL_END
