//  IMDetailMemberCell.h
//  详情页「成员行」Cell（头像 + 名 + uid 副行 + 群主/管理员角标）。从 IMChatDetailViewController.m 抽出，未改行为。

#import <UIKit/UIKit.h>

@class IMGroupMember;

NS_ASSUME_NONNULL_BEGIN

@interface IMDetailMemberCell : UITableViewCell
- (void)configureWithMember:(IMGroupMember *)m isMe:(BOOL)isMe;
@end

NS_ASSUME_NONNULL_END
