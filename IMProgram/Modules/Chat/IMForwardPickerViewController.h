//  IMForwardPickerViewController.h
//  转发/分享选择页（#6）：整页展示会话列表，右上「多选」切换单选/多选（多选最多 9 个）。
//  自身只负责选择，选中的会话由 onDone 回调交回调用方去转发（可复用于其它"选会话"场景）。
//
//  2026-11 分享选择页改造（IMServer/docs/design/sketches/SHARE_PICKER_UX_SKETCH.html）：
//  · 列表上方「我的好友」「我的群聊」两个入口（push 子页 IMShareContactListViewController），
//    没聊过的好友 / 删过会话的群也能选——回调里交回的是**合成的** IMConversation（convID 本地推导），
//    调用方只用 convID / isGroup / peer，故无需改动；
//  · 选中集 = IMShareSelection（按 conv_id 去重、三处合计上限 9），三页共用、勾选状态互通；
//  · 多选态底部常驻已选栏（IMShareSelectionBar，复用建群页已选成员横条），「发送(N)」在栏上；
//    点发送先弹确认面板（IMShareConfirmViewController）再回调 onDone；
//  · 搜索同时搜最近聊天 / 好友 / 群聊，按 conv_id 去重分组。

#import <UIKit/UIKit.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMForwardPickerViewController : UIViewController

/// host/token 用于拉取会话列表；onDone 回调选中的会话（单选=1 个，多选=1..9 个）；页面自身负责收起。
- (instancetype)initWithHost:(NSString *)host
                       token:(NSString *)token
                      onDone:(void (^)(NSArray<IMConversation *> *selected))onDone NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

// 以下均为可选配置，须在 viewDidLoad 跑之前（present/push 前）设好；不设保留转发流程原行为不变。
// 「添加例外」会话选择页（NOTIFICATIONS_P1_DESIGN §2）复用本页时用得上，其余调用方无需理会。

/// 附加过滤：在系统通知会话已被剔除之后应用（loadConversations 内建的那一条剔除**始终生效**，
/// 与本 block 无关）。默认 nil = 不过滤。
@property (nonatomic, copy, nullable) BOOL (^extraFilter)(IMConversation *conversation);

/// 覆盖导航栏标题；默认 nil 用 forward.picker.destination_title。
@property (nonatomic, copy, nullable) NSString *titleOverride;

/// 表尾脚注文案；默认 nil 不显示。
@property (nonatomic, copy, nullable) NSString *footerText;

/// 空态文案。默认 nil：保留转发流程原行为（零会话时弹 toast，列表不显示任何空态视图）。
/// 非空时：零会话（含搜索无匹配）改为持续显示居中空态标签，不再弹 toast。
@property (nonatomic, copy, nullable) NSString *emptyText;

/// YES：单选态下**不显示**「多选」入口，点一行**立即**回调 onDone 并收起，不再弹「确认转发」对话框
/// （NOTIFICATIONS_P1_DESIGN §2「点一行 → 立即设免打扰 → 关闭选择页」）。默认 NO，转发流程行为不变。
@property (nonatomic, assign) BOOL immediateSingleSelect;

/// 是否显示「我的好友 / 我的群聊」入口（并让搜索覆盖好友与群）。默认 YES；
/// 「添加例外」页传 NO——它选的是"已有会话的免打扰"，没会话的好友 / 群在那里无意义。
@property (nonatomic, assign) BOOL showsContactEntries;

/// 不作为目标的用户（单聊会话与好友列表里都剔除）。分享某人的名片时传他自己——把 A 的名片发给 A 没有意义
/// （三端同口径，Android `ForwardPickerScreen(exclude=)`）。
@property (nonatomic, copy, nullable) NSSet<NSString *> *excludedUserIDs;

/// 不作为目标的会话（最近聊天 / 群聊 / 搜索里都剔除）。分享群邀请时传该群——把群的邀请发回群里没有意义。
@property (nonatomic, copy, nullable) NSSet<NSString *> *excludedConvIDs;

/// 本人 uid（推导好友 conv_id 用）。调用方手上有就传；nil 时回退 IMSocketManager.userID。
/// 两者都拿不到时不显示「我的好友 / 我的群聊」入口（没有 uid 推不出单聊 conv_id）。
@property (nonatomic, copy, nullable) NSString *selfUID;

/// 多选确认面板里的内容预览（如「[名片] 张三」「[图片]」）。nil = 不显示预览行。
@property (nonatomic, copy, nullable) NSString *previewText;

@end

NS_ASSUME_NONNULL_END
