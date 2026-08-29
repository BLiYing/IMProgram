//  IMDetailContactCell.h
//  个人名片的「列表行」——**会话详情页「名片」页签**与**收藏页「名片」分类共用同一个 cell**
//  （即"收藏页复用资料详情页"的落地方式，与 IMDetailFileCell 被两处复用一脉相承）。
//  规格见 docs/design/CONTACT_CARD_DESIGN.md §7.1：行高 64、头像 44、主行显示名、副行 `ID x[· 由 X 分享]`、右上时间。

#import <UIKit/UIKit.h>

@class IMContactCard;

NS_ASSUME_NONNULL_BEGIN

/// 行高（成员行 60 / 文件行 74 之间：两行文字 + 44 头像的自然高度）。
FOUNDATION_EXPORT const CGFloat IMDetailContactCellHeight;

@interface IMDetailContactCell : UITableViewCell

/// card：解析后的名片。**传 nil = 清空该行**——脏名片本不该收录进列表（见 §7.2），
/// 但 cell 是复用的：真走到这条路而只是 `return cell` 的话，屏幕上会留着**上一行**的名字和头像。
/// displayName：收方本地显示名（备注 > 快照昵称 > uid）。
/// sourceName：来源显示名，非空 → 副行追加「· 由 X 分享」（群聊详情页 / 收藏页用；单聊详情页传 nil）。
/// timestampMillis：分享时间；<=0 不显示。
- (void)configureWithCard:(nullable IMContactCard *)card
              displayName:(nullable NSString *)displayName
               sourceName:(nullable NSString *)sourceName
          timestampMillis:(int64_t)timestampMillis;

@end

NS_ASSUME_NONNULL_END
