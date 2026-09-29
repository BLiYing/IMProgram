//  IMForwardPickerViewController.h
//  转发/分享选择页（#6）：整页展示会话列表，右上「多选」切换单选/多选（多选最多 9 个）。
//  自身只负责选择，选中的会话由 onDone 回调交回调用方去转发（可复用于其它"选会话"场景）。

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

@end

NS_ASSUME_NONNULL_END
