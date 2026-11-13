//  IMFriendCacheWriter.h
//  本地好友快照（im_friend_local）的读种子 + 「变了才写」落库，通讯录首页与「我的好友」页共用。
//
//  为什么抽出来（2026-11-13 通讯录首页改版）：好友列表搬到 IMFriendListViewController 后，两个页面都会
//  拉到权威名单。指纹若各记各的，A 页写了新名单、B 页拿着旧指纹再收到旧名单时会误判「没变」而不写，
//  库里就留下错的那份。所以指纹只能有一份，跟着库走、不跟着页面走。
//  首页仍然要写：全局搜索 / 收藏 / 资料页都读这份快照，不能等用户点进「我的好友」才更新。

#import <Foundation/Foundation.h>

@class IMUserCard, IMDatabaseAccountContext;

NS_ASSUME_NONNULL_BEGIN

/// 全部方法只在主线程调用。
@interface IMFriendCacheWriter : NSObject

/// 读本地好友快照（离线首屏种子），并把读到的内容记为当前指纹。context 为 nil / 已失效返回空数组。
+ (NSArray<IMUserCard *> *)cachedFriendsWithContext:(nullable IMDatabaseAccountContext *)context;

/// 权威好友名单（仅 accepted）落库，供下次离线首屏。空名单也写，代表当前账号无好友。
/// 比较基准：有已入队未写完的名单就和它比（写队列排空后库里就是它），否则和已写成的指纹比；一致就不写。
/// 变了才在后台串行队列整表重写：入队即记为「待写指纹」，写成后升为已写成指纹，写失败清掉待写（下次重试）。
+ (void)persistFriendsIfChanged:(NSArray<IMUserCard *> *)accepted
                        context:(nullable IMDatabaseAccountContext *)context;

@end

NS_ASSUME_NONNULL_END
