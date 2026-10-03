//  IMDetailServerArchive.h
//  资料页「媒体 / 文件 / 语音」页签的服务端分页持有者（OFFLINE_BACKLOG_DESIGN §4.9 第 5 项；对称 Web `useDetailServerArchive`、
//  Android `ConvArchive`）。
//
//  页签数据源原本只是本地归档（`IMDatabase archiveMessagesForConv:`）。本地有缺口且在线时缺口里的图 / 文件 / 语音本地没有，
//  页签给的是看着正常其实残缺的答案：这时按类型向 `GET /conversations/{id}/media` 要（新→旧、游标分页），与本地**取并集**
//  （两边都是事实，按 convSeq 去重、本地优先）。链接页签服务端没有可索引的列，仍只看本地。
//  主线程使用。

#import <Foundation/Foundation.h>
#import "IMChatDetailTabs.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 并集：本地优先（字段更全），按 convSeq 去重；`convSeq<=0` 的服务端项不收。纯函数，见 IMDetailServerArchiveTests。
extern NSArray<IMMessageModel *> *IMDetailArchiveUnion(NSArray<IMMessageModel *> *local, NSArray<IMMessageModel *> *server);

@interface IMDetailServerArchive : NSObject

- (instancetype)initWithConvID:(NSString *)convID clearedUpTo:(int64_t)clearedUpTo;

/// 三类各要第一页；全部回来（或失败）后回调一次（主线程）。
- (void)loadFirstPages:(void (^)(BOOL anyFailed))completion;

/// 某些消息被物理移除（为所有人删除 / 仅为我删除）后同步剔除：否则下次并集时「本地没有就收服务端」会让它们复活。
- (void)removeMessagesWithConvSeqs:(NSSet<NSNumber *> *)seqs;

/// 本地 ∪ 服务端已拉到的。
- (NSArray<IMMessageModel *> *)mergedWithLocal:(NSArray<IMMessageModel *> *)local;

/// 该页签是否由服务端分页供给（媒体 / 文件 / 语音）。链接 / 名片 / 成员恒 NO。
+ (BOOL)kindIsArchived:(IMDetailTabKind)kind;
- (BOOL)hasMoreForKind:(IMDetailTabKind)kind;
- (BOOL)isLoadingKind:(IMDetailTabKind)kind;
/// 取该类下一页；回调主线程。失败 = 离线降级（该类停在已有的，`error` 非空）。
- (void)loadMoreForKind:(IMDetailTabKind)kind completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
