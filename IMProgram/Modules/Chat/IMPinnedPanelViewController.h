//  IMPinnedPanelViewController.h
//  置顶消息底部面板：一段「只读的聊天」——壁纸底 + 聊天页同款真气泡（IMBubbleCell / IMImageCell / IMVoiceBubbleCell /
//  IMLinkCardCell / IMContactCardCell / IMChatRecordCell / IMCallRecordCell，readOnly），每条紧挨气泡一枚「定位到聊天位置」
//  图标（我发的在气泡左、别人的在气泡右）；长按气泡出过滤后的菜单（取消置顶 / 复制 / 定位）；有权限者底栏「取消所有置顶」。
//  形态同 IMChatDateJumpViewController：PageSheet（medium + large）+ grabber + 自持 IMLiquidNavigationBar（左 ✕）。
//  设计：IMServer docs/design/PINNED_PANEL_DESIGN.md + sketches/PINNED_PANEL_UX_SKETCH.html（1:1，以稿为准）。
//
//  宿主（聊天页）只负责：present 一行、把置顶集合变化推进来（applyPinnedItems:）、实现 IMPinnedPanelHost。

#import <UIKit/UIKit.h>
#import "IMGroupInfo.h" // IMGroupRole

@class IMPinnedPanelViewController;
@class IMPinnedMessage;
@class IMMessageModel;
@class IMMentionSpan;
@class IMDatabase;
@class IMMediaDownloadCoordinator;

NS_ASSUME_NONNULL_BEGIN

/// 面板向聊天页借的能力。前半段是聊天页**已有**的渲染/查库/跳转方法（同一份口径，面板不另写），
/// 后两个是面板专用的回写入口。
@protocol IMPinnedPanelHost <NSObject>
@property (nonatomic, copy, readonly) NSString *convID;
@property (nonatomic, copy, readonly) NSString *userID;
@property (nonatomic, assign, readonly) BOOL isGroupChat;
/// 下载门控（M4-7）：收到的图/视频按策略未下载时只显占位，不因进了面板就偷拉原图。
@property (nonatomic, strong, readonly) IMMediaDownloadCoordinator *downloads;
- (BOOL)canPinMessages;
- (NSString *)senderNameForMessage:(IMMessageModel *)m;
- (IMGroupRole)senderRoleForMessage:(IMMessageModel *)m;
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m;
- (NSString *)fullMediaURL:(NSString *)content;
- (NSDictionary<NSString *, NSString *> *)mentionMapForMessage:(IMMessageModel *)m;
- (NSDictionary<NSString *, NSString *> *)mentionMapForCaption:(IMMessageModel *)m;
- (nullable NSArray<IMMentionSpan *> *)mentionSpansForMessage:(IMMessageModel *)m;
- (nullable NSArray<IMMentionSpan *> *)mentionSpansForCaption:(IMMessageModel *)m;
- (NSString *)replyFromNameForUID:(NSString *)uid;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;
/// 定位（面板先收起再调）：已含「目标已撤回 → toast + 重拉」。
- (void)jumpToPinnedConvSeq:(int64_t)convSeq;
- (void)reloadPinnedBanner;
/// 长按「取消置顶」：只作用于所长按那条（发 pin msg_op pinned=false，不确认）。
- (void)pinnedPanel:(IMPinnedPanelViewController *)panel unpinConvSeq:(int64_t)convSeq;
/// 面板本地改了集合（取消一条后的乐观摘除 / 取消所有成功后清空）：宿主同步横幅。
- (void)pinnedPanel:(IMPinnedPanelViewController *)panel didChangeItems:(NSArray<IMPinnedMessage *> *)items;
@end

@interface IMPinnedPanelViewController : UIViewController

- (instancetype)initWithHost:(id<IMPinnedPanelHost>)host items:(NSArray<IMPinnedMessage *> *)items NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, readonly, nullable) id<IMPinnedPanelHost> host;
/// 当前置顶集合（pinned_at 降序，服务端顺序）。
@property (nonatomic, copy, readonly) NSArray<IMPinnedMessage *> *items;

/// 实时刷新（宿主横幅集合变化时推进来）：重铺行；集合为空自动收起面板。
- (void)applyPinnedItems:(NSArray<IMPinnedMessage *> *)items;

/// 长按菜单「取消置顶」的落点：只摘 convSeq 这一条（本地淡出 + 通知宿主发 op），其余不动。暴露给单测。
- (void)unpinConvSeq:(int64_t)convSeq;

@end

NS_ASSUME_NONNULL_END
