//  IMHTTPService+Folders.h
//  会话文件夹 REST（IMServer/docs/PROTOCOL.md §6.15 / §11）。所有写接口成功后回的都是整表
//  `{version, folders[], limits}`（与 folder_update 帧同形），由 IMChatFolderStore 整表替换。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMFolderCompletion)(NSDictionary *_Nullable data, NSError *_Nullable error);

@interface IMHTTPService (Folders)

- (void)foldersWithToken:(NSString *)token completion:(IMFolderCompletion)completion;
- (void)createFolderWithToken:(NSString *)token name:(NSString *)name convIDs:(NSArray<NSString *> *)convIDs
                     clientID:(NSString *)clientID completion:(IMFolderCompletion)completion;
- (void)renameFolderWithToken:(NSString *)token folderID:(NSString *)folderID name:(NSString *)name
                   completion:(IMFolderCompletion)completion;
- (void)deleteFolderWithToken:(NSString *)token folderID:(NSString *)folderID completion:(IMFolderCompletion)completion;
- (void)reorderFoldersWithToken:(NSString *)token folderIDs:(NSArray<NSString *> *)folderIDs
                     completion:(IMFolderCompletion)completion;
- (void)changeFolderConvsWithToken:(NSString *)token folderID:(NSString *)folderID
                               add:(NSArray<NSString *> *)add remove:(NSArray<NSString *> *)remove
                        completion:(IMFolderCompletion)completion;

@end

NS_ASSUME_NONNULL_END
