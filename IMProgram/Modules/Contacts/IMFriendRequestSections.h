//  IMFriendRequestSections.h
//  「新的朋友」页的分段逻辑（纯函数，无 UI，便于单测）。
//  口径见 ../IMServer/docs/design/NEW_FRIENDS_DESIGN.md §1：
//  待我确认(pending) → 已发出(requested) → 已添加(accepted 且 updated_at 在最近 30 天、倒序、至多 50 条)。

#import <Foundation/Foundation.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 「已添加」只取最近这么多天内成为好友的人。
extern const NSInteger kIMRecentAddedDays;
/// 「已添加」最多显示条数（更早的好友去通讯录找）。
extern const NSInteger kIMRecentAddedMax;

@interface IMFriendRequestSections : NSObject

@property (nonatomic, copy, readonly) NSArray<IMUserCard *> *incoming;  // status == Pending
@property (nonatomic, copy, readonly) NSArray<IMUserCard *> *outgoing;  // status == Requested
@property (nonatomic, copy, readonly) NSArray<IMUserCard *> *added;     // 最近 30 天内 Accepted，updatedAt 倒序，≤50

/// 全空（三段都没有）才该显示空态文案。
@property (nonatomic, readonly) BOOL isEmpty;

/// nowMs：当前时间（毫秒），由调用方注入以便测试边界。
+ (instancetype)sectionsWithCards:(nullable NSArray<IMUserCard *> *)cards nowMs:(int64_t)nowMs;

@end

NS_ASSUME_NONNULL_END
