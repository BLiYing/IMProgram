//  IMHTTPService+Folders.m

#import "IMHTTPService+Folders.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (Folders)

- (void)runFolderRequest:(NSMutableURLRequest *)req completion:(IMFolderCompletion)completion {
    // runDataRequest 保留业务码（CODING_STYLE §5）：调用方按 error.code 取 err.<code> 文案。
    [self runDataRequest:req fallback:IMLocalized(@"folder.toast.failed") completion:completion];
}

- (void)foldersWithToken:(NSString *)token completion:(IMFolderCompletion)completion {
    [self runFolderRequest:[self authedRequestForPath:@"/api/v1/folders" method:@"GET" token:token body:nil]
                completion:completion];
}

- (void)createFolderWithToken:(NSString *)token name:(NSString *)name convIDs:(NSArray<NSString *> *)convIDs
                     clientID:(NSString *)clientID completion:(IMFolderCompletion)completion {
    NSMutableDictionary *body = [@{ @"name": name ?: @"", @"conv_ids": convIDs ?: @[] } mutableCopy];
    if (clientID.length > 0) { body[@"client_id"] = clientID; } // 网络重发时服务端据此回既存结果而非报重名
    [self runFolderRequest:[self authedRequestForPath:@"/api/v1/folders" method:@"POST" token:token body:body]
                completion:completion];
}

- (void)renameFolderWithToken:(NSString *)token folderID:(NSString *)folderID name:(NSString *)name
                   completion:(IMFolderCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/folders/%@", [self pathEscape:folderID]];
    [self runFolderRequest:[self authedRequestForPath:path method:@"PATCH" token:token body:@{ @"name": name ?: @"" }]
                completion:completion];
}

- (void)deleteFolderWithToken:(NSString *)token folderID:(NSString *)folderID completion:(IMFolderCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/folders/%@", [self pathEscape:folderID]];
    [self runFolderRequest:[self authedRequestForPath:path method:@"DELETE" token:token body:nil] completion:completion];
}

- (void)reorderFoldersWithToken:(NSString *)token folderIDs:(NSArray<NSString *> *)folderIDs
                     completion:(IMFolderCompletion)completion {
    [self runFolderRequest:[self authedRequestForPath:@"/api/v1/folders/order" method:@"PUT" token:token
                                                  body:@{ @"ids": folderIDs ?: @[] }]
                completion:completion];
}

- (void)changeFolderConvsWithToken:(NSString *)token folderID:(NSString *)folderID
                               add:(NSArray<NSString *> *)add remove:(NSArray<NSString *> *)remove
                        completion:(IMFolderCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/folders/%@/convs", [self pathEscape:folderID]];
    [self runFolderRequest:[self authedRequestForPath:path method:@"POST" token:token
                                                  body:@{ @"add": add ?: @[], @"remove": remove ?: @[] }]
                completion:completion];
}

@end
