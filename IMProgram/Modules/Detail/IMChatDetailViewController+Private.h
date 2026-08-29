//  IMChatDetailViewController+Private.h
//  详情页的**私有类扩展**（原内联在 IMChatDetailViewController.m）。抽到共享私有头后，详情页实现可拆成
//  多个分文件 category（+Header / +Actions …）共享同一份私有属性/协议/常量。同 IMChatViewController+Private.h
//  的约定：跨 category 互调的私有方法在文末 (Private) 分类登记；ivar 直接访问只在主实现文件。

#import <UIKit/UIKit.h>
#import "IMChatDetailViewController.h"
#import "IMProgram-Swift.h"   // IMLiquidNavigationBar / IMLiquidNavigationBarDelegate（Swift 桥接）

@class IMDatabaseAccountContext;
@class IMGroupInfo;
@class IMDetailHeaderContainer;
@class IMDetailAvatarView;
@class IMDetailMediaContainerCell;
@class IMTelegramAvatarEffectsView;
@class IMTelegramAvatarMaskView;
@class IMDropletHeaderMorph;
@class IMLiquidSegmentedControl;
@class IMChatDetailTab;
@class IMMediaItem;
@class IMMessageModel;
@class IMMediaDownloadCoordinator;
@class IMDatabase;

NS_ASSUME_NONNULL_BEGIN

/// 夹取到 [a,b]（头部形变/滚动多处共用；static inline 供各 category TU 各自内联，无链接冲突）。
static inline CGFloat IMClamp(CGFloat x, CGFloat a, CGFloat b) { return MIN(MAX(x, a), b); }

/// 页面分区（动态组装到 _sections）。
typedef NS_ENUM(NSInteger, IMDetailSection) {
    IMDetailSectionInfo = 0,   ///< 单聊：备注名 / 用户名
    IMDetailSectionAbout,      ///< 群公告 / 群简介（群聊·全员只读·非空才显，G1 修·决策 17）
    IMDetailSectionSettings,   ///< 置顶 / 免打扰（+群主管理员：群管理）
    IMDetailSectionTabs,       ///< 分类页签内容（header=分段控件）
};

/// 布局常量（原文件级 static const，抽到共享头供各 category 共用；定义在主实现文件）。
FOUNDATION_EXPORT CGFloat const kIMDetailPillsRowH;
FOUNDATION_EXPORT CGFloat const kIMDetailTabBarH;          ///< 页签栏高度（含分段控件上下留白）；分段控件本体 = kIMDetailTabBarH-12
FOUNDATION_EXPORT CGFloat const kIMDetailTabSegH;          ///< 分段控件本体高度（点击面积）
FOUNDATION_EXPORT CGFloat const kIMDetailNavOpaqueOnCollapse; ///< 标题栏「变实」上限（头部收拢完成时的不透明度）

@interface IMChatDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate, IMLiquidNavigationBarDelegate>
// 身份
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
// 单聊对端
@property (nonatomic, copy, nullable) NSString *peerID;
@property (nonatomic, copy, nullable) NSString *peerNickname; ///< 对端真实昵称（不含备注，备注在 peerRemark）
/// `peerNickname` 是否已被 +Peer.m 的 loadPeerProfile 用服务端权威值覆盖过。
/// **init 传入的那个值不可信**：各入口给的东西不一样——会话列表给真实昵称、群成员行给的是
/// `IMGroupMember.displayName`（**群昵称优先**）、找人搜索给的是 nil。名片快照必须冻结真实昵称，
/// 故「推荐给朋友」在此标志为 NO 时先拉一次再发（/code-review 2026-08-29）。
@property (nonatomic, assign) BOOL peerProfileLoaded;
/// 我给对端起的备注名（仅本人可见、多端同步）：非空即替代昵称作标题/头像首字母。
/// 权威值在服务端 im_friend.remark；本页值由 IMRemarkStore 供给（loadPeerBlockState 顺路刷新）。
@property (nonatomic, copy, nullable) NSString *peerRemark;
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;
@property (nonatomic, assign) BOOL peerBlocked;
// 好友准入（微信式，任务一 P0）：非好友不显示「消息/呼叫/视频」，改显「加好友」。
// 乐观默认 YES（多数单聊入口=已有好友），loadPeerBlockState 拉到关系后校正并重建操作排。
@property (nonatomic, assign) BOOL peerIsFriend;
// 群成员长按菜单用：我的 accepted 好友 uid 集合（决定成员菜单显「发送消息」还是「添加好友」）。
@property (nonatomic, strong, nullable) NSSet<NSString *> *friendUIDs;
// showsMessagePill 已提升为公开属性（见 .h）：单聊从群成员/通讯录等外部进入时显示「消息」入口。
// 群
@property (nonatomic, copy, nullable) NSString *groupName;
@property (nonatomic, strong, nullable) IMGroupInfo *group;
// 会话设置
@property (nonatomic, assign) int64_t pinnedAt;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL markedUnread; ///< 手动标未读态：PUT 是整体替换，提交时必须回传，否则会清掉列表页设的红点
@property (nonatomic, copy, nullable) NSString *convRemark; ///< 会话备注（G1，仅本人可见、多端同步）：从服务端读，非空替代群名显示
// UI
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMDetailHeaderContainer *headerContainer; ///< 静态坐标容器：承载头像 + 灵动岛遮罩/覆盖层
@property (nonatomic, strong) IMDetailAvatarView *avatarView;
@property (nonatomic, strong) UIView *dropletBottomCover;                  ///< 灵动岛下方黑底（Telegram bottomCoverNode）
@property (nonatomic, strong) IMTelegramAvatarEffectsView *dropletTopCover;///< 顶部 blur+gradient+fade（topCoverNode）
@property (nonatomic, strong) IMTelegramAvatarMaskView *dropletMask;       ///< 171pt Lottie（UserAvatarMask）
@property (nonatomic, strong) UILabel *nameOnImage;   ///< 图上名（photo 模式顶部）
@property (nonatomic, strong) UILabel *subOnImage;
@property (nonatomic, strong) UILabel *nameBelow;     ///< 圆头像下居中名
@property (nonatomic, strong) UILabel *subBelow;
@property (nonatomic, strong) IMLiquidNavigationBar *liquidNavigationBar;
@property (nonatomic, strong) IMDropletHeaderMorph *headerMorph; ///< 共享 Zone① 头部形变驱动（与「我」页同一套）
@property (nonatomic, strong) UIView *pillsView;            ///< 搜索/更多独立按钮，放在 tableHeader 中避开 grouped 卡片背景
// 页签
@property (nonatomic, strong) IMLiquidSegmentedControl *segmented;
@property (nonatomic, strong) UIView *stickyBar;               ///< 页签滚到顶时的悬浮吸顶条（透明，仅托分段控件）
@property (nonatomic, strong) IMLiquidSegmentedControl *stickySeg;   ///< 吸顶条内镜像分段控件
@property (nonatomic, strong) NSArray<IMChatDetailTab *> *tabs;
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, strong) NSArray<IMMediaItem *> *tabMedia;    ///< 当前媒体项（媒体页签）
@property (nonatomic, strong) NSArray<IMMessageModel *> *tabMediaMessages; ///< 与 tabMedia **逐位对齐**的消息模型（下载态/thumb 取自它）
@property (nonatomic, strong) NSArray<IMMessageModel *> *tabRows;  ///< 当前文件/语音/链接消息
/// 媒体/文件 Tab 的下载编排（M4-7）：与聊天页共用 IMMediaDownloadCoordinator，同一份文件天然共享一个下载态。
@property (nonatomic, strong) IMMediaDownloadCoordinator *downloads;
@property (nonatomic, weak, nullable) IMDetailMediaContainerCell *mediaContainerCell; ///< 只刷单格用（避免整行重建）
@property (nonatomic, assign) CGFloat mediaGridWidth;   ///< 宫格 cell 的真实内容宽（0=未知，由 cell 上报）
// 布局
@property (nonatomic, assign) BOOL hasPhoto;
@property (nonatomic, assign) CGFloat topInset;
@property (nonatomic, assign) BOOL didHapticCircle;
@property (nonatomic, assign) BOOL didHapticAbsorb;
@end

/// 跨分文件 category 互调的私有方法：主实现与各 category 都 import 本头。按业务概念粗分组、不标注定义文件
/// （方法会在 category 间搬家，硬写文件名会失真；定义位置按 selector 跳转）。
@interface IMChatDetailViewController (Private)
// 头部 / 页签 / 构建（+Header.m）：
- (void)buildTableView;
- (void)buildHeaderOverlay;
- (void)rebuildPillsView;
- (void)updatePillsVisibility;
- (void)applyHeaderMorph;
- (CGFloat)headerCollapseOffset;
- (CGFloat)tabPinTop;
- (void)addTabPinTapTo:(IMLiquidSegmentedControl *)seg;
- (NSString *)headerAvatarURL;
- (NSString *)displayTitle;
- (NSString *)displaySubtitle;
- (void)refreshHeaderTexts;
- (void)rebuildTabs;
- (IMDetailSection)sectionKindAt:(NSInteger)index;
- (NSInteger)indexOfSection:(IMDetailSection)kind;
- (void)updateStickyTabs;
- (CGFloat)pinOffset;
- (NSString *)currentConvRemark;
- (CGFloat)tabBarHeight;
- (NSArray<NSDictionary *> *)actionPillSpecs;
- (UIButton *)actionPillButtonForSpec:(NSDictionary *)spec;
- (UIView *)buildPillsView;
// 动作 / 设置 / 群昵称备注（+Actions.m）：
- (void)commitConversationSettings;
- (void)loadConversationSettings; ///< 拉取会话设置（提交失败时 +Actions 回拉权威值刷新开关）
- (void)confirmClearHistory;
- (void)confirmDestructive:(NSString *)title message:(NSString *)message action:(NSString *)action handler:(void (^)(void))handler;
- (void)confirmDissolve;
- (void)confirmLeaveGroup;
- (void)editGroupRemark;
- (void)editMyGroupNickname;
- (void)editRemark;
- (void)moreTapped:(UIButton *)anchor;
- (void)openChatWithPeerID:(NSString *)peerID nickname:(nullable NSString *)nickname avatarURL:(nullable NSString *)avatarURL;
- (void)pillTapped:(UIButton *)b;
- (void)requestAddFriendUID:(NSString *)uid;
- (void)requestAddPeerFriend;
- (void)switchChanged:(UISwitch *)sw;
- (void)toggleBlock;
// 数据加载 / DB（主实现）：
- (void)loadGroupInfo;
- (void)loadFriendUIDs;
- (void)loadPeerBlockState;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;
// target-action 选择器（+Header setup 用 @selector 接线，方法体在主实现/其它 category）：
- (void)tabBarTapped;
- (void)avatarTapped;
- (void)stickySegChanged:(IMLiquidSegmentedControl *)seg;
- (void)swipeToNextTab:(UISwipeGestureRecognizer *)g;
- (void)swipeToPrevTab:(UISwipeGestureRecognizer *)g;
- (void)playVoiceRow:(IMMessageModel *)m; // 语音 tab 点行播放（+Actions.m，2026-08-26）
/// 装配语音 tab 三行 cell 内容（发送者/语音·m:ss/年月日时分）。放 +Actions.m 是体量门禁拆分——
/// 主 VC 曾一路涨到 1508>1500 红线（2026-08-27 拆）。
- (void)decorateVoiceRow3Cell:(UITableViewCell *)cell message:(IMMessageModel *)m;

// —— 单聊对端权威资料（IMChatDetailViewController+Peer.m）——
/// 进页拉一次 GET /users/{id} 覆盖 init 传入的快照；404 → 空态。单聊专用。
- (void)loadPeerProfile;
/// 「该用户不存在或已注销」空态覆盖层（幂等）。
- (void)showPeerNotFoundState;

// —— 名片页签（IMChatDetailViewController+Contacts.m）——
/// 名片行 cell（详情页「名片」签）。message 必须已通过 matchesKind: 的解析校验。
- (UITableViewCell *)contactRowCellIn:(UITableView *)tv message:(IMMessageModel *)m;
/// 点名片行 → 名片里那个人的资料页（与点聊天气泡同一落点）。
- (void)openContactRowAtIndex:(NSInteger)row;
/// 由一条名片消息进对方资料页（气泡/详情行/收藏行三处共用的落点，见设计文档 §6）。
- (void)openProfileForContactMessage:(IMMessageModel *)m;
@end

NS_ASSUME_NONNULL_END
