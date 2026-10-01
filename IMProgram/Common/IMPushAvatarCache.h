//  IMPushAvatarCache.h
//  通知扩展的头像缓存（M5，PUSH_M5_DESIGN §3.6）。与 IMPushSender 一样**同编进扩展**，只依赖 Foundation。
//
//  · 按头像地址缓存：服务端头像是内容寻址（/avatars/<sha256>.jpg），换头像 = 换地址，缓存天然跟着换，
//    不存在「地址没变、内容变了」要失效的情况。
//  · 另记每个人 / 每个群「最近一次的头像」：对方刚换了头像、手机又恰好连不上服务器时，先显示旧头像
//    （认得出是谁），比退回 App 图标有用；等连上了下一条推送自然换成新的。
//  · 清理：超过 30 天没用过的删掉，总量超过 20MB 先删最久没用的。头像几十 KB，够存几百个。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 缓存条目（清理计划用）：文件名、字节数、最后使用时间。
@interface IMPushAvatarCacheEntry : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) unsigned long long bytes;
@property (nonatomic, strong, readonly) NSDate *lastUsed;
+ (instancetype)entryWithName:(NSString *)name bytes:(unsigned long long)bytes lastUsed:(NSDate *)lastUsed;
@end

/// 纯函数：头像路径对应的缓存文件名（`/avatars/<sha>.jpg` → `<sha>.jpg`）。不是合法头像路径返回 nil。
FOUNDATION_EXPORT NSString *_Nullable IMPushAvatarCacheFileName(NSString *_Nullable avatarPath);

/// 纯函数：该删哪些文件。先删超过 maxAge 没用过的；剩下的总量仍超过 maxBytes，按最久没用的顺序删到不超。
FOUNDATION_EXPORT NSArray<NSString *> *IMPushAvatarCachePlanEviction(NSArray<IMPushAvatarCacheEntry *> *entries,
                                                                     NSDate *now, NSTimeInterval maxAge,
                                                                     unsigned long long maxBytes);

/// 缓存本体（扩展用；目录在 App Group 容器里，App Group 不可用时所有读写都是空操作）。
@interface IMPushAvatarCache : NSObject
+ (instancetype)shared;
/// 按头像路径取缓存的图片数据（命中会刷新「最后使用时间」）；没有返回 nil。
- (nullable NSData *)dataForAvatarPath:(nullable NSString *)avatarPath;
/// 下载成功后存一份，并把它记为 owner（如 `u:<uid>` / `g:<conv_id>`）最近一次的头像。
- (void)storeData:(NSData *)data forAvatarPath:(NSString *)avatarPath owner:(NSString *)owner;
/// owner 最近一次的头像（方案 A：新头像取不到时退回它）。
- (nullable NSData *)lastKnownDataForOwner:(NSString *)owner;
/// 按上面的规则清理一次；一天最多真正扫一次目录。
- (void)evictIfNeeded;
@end

NS_ASSUME_NONNULL_END
