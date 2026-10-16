//  IMChatFolderStore.h
//  会话文件夹的客户端状态（按账号隔离）：整表快照 + 单调版本，REST 写入与 folder_update 帧都走
//  `applySnapshot:`（版本 ≤ 本地的丢弃）。设计见 IMServer/docs/design/CHAT_FOLDERS_DESIGN.md §3。
//
//  落盘（冷启动先画 Tab 条，随后被 GET 覆盖）：NSUserDefaults `im.chatFolders.<uid>`，内容即快照 JSON。
//  所有方法与回调都在主线程。

#import <Foundation/Foundation.h>
#import "IMChatFolder.h"

NS_ASSUME_NONNULL_BEGIN

/// 文件夹整表变化（含版本推进、换账号加载）。主线程。
extern NSNotificationName const IMChatFoldersDidChangeNotification;

@interface IMChatFolderStore : NSObject

+ (instancetype)shared;

@property (nonatomic, copy, readonly) NSArray<IMChatFolder *> *folders;
@property (nonatomic, assign, readonly) int64_t version;
/// 服务端下发的上限（`limits`）；未拿到时用设计默认值 10 / 100 / 12。
@property (nonatomic, assign, readonly) NSInteger maxFolders;
@property (nonatomic, assign, readonly) NSInteger maxConvs;
@property (nonatomic, assign, readonly) NSInteger maxNameLength;

/// 开始观察 socket 连接态 / folder_update 帧并首次同步（App 启动调一次，幂等）。
- (void)start;

/// 切到账号 uid：与当前不同则清内存、读该账号落盘。幂等。
- (void)adoptUserID:(nullable NSString *)userID;

/// GET /folders 整表拉取（未登录静默跳过）。
- (void)refresh;

/// 应用一份整表快照（`{version, folders[], limits?}`）。版本 ≤ 本地版本的丢弃，返回是否真的应用了。
- (BOOL)applySnapshot:(NSDictionary *)data;

- (nullable IMChatFolder *)folderWithID:(NSString *)folderID;
/// 含该会话的全部文件夹（按 position 升序）。
- (NSArray<IMChatFolder *> *)foldersContainingConv:(NSString *)convID;

#pragma mark - 写操作（服务端权威：成功后用回包整表替换；失败回调 error，业务码保留）

- (void)createFolderNamed:(NSString *)name convIDs:(NSArray<NSString *> *)convIDs
               completion:(void (^)(IMChatFolder *_Nullable folder, NSError *_Nullable error))completion;
- (void)renameFolder:(NSString *)folderID to:(NSString *)name completion:(void (^)(NSError *_Nullable error))completion;
- (void)deleteFolder:(NSString *)folderID completion:(void (^)(NSError *_Nullable error))completion;
- (void)reorderFolderIDs:(NSArray<NSString *> *)ids completion:(void (^)(NSError *_Nullable error))completion;
- (void)changeConvsInFolder:(NSString *)folderID add:(NSArray<NSString *> *)add remove:(NSArray<NSString *> *)remove
                 completion:(void (^)(NSError *_Nullable error))completion;

/// 面向用户的错误文案：文件夹业务码（300301–300305）查 `err.<code>`；其余用 error 自带文案，兜底「操作失败，请重试」。
+ (NSString *)userMessageForError:(NSError *)error;

/// 清空内存与本账号的落盘快照（注销账号清本机缓存用；测试也用它）。
- (void)wipeLocalState;
/// 仅测试：同 wipeLocalState。
- (void)resetForTesting;

@end

NS_ASSUME_NONNULL_END
