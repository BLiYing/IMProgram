//  IMChatFolderConvCell.h
//  聊天文件夹编辑页 / 会话选择器共用的会话行：头像圈 + 显示名，可选勾选态（accessory checkmark）。

#import <UIKit/UIKit.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatFolderConvCell : UITableViewCell
/// checked = nil 表示不显示勾选态（编辑页已添加列表）；YES/NO 为选择器的勾选态。
- (void)configureWithConversation:(IMConversation *)conv checked:(nullable NSNumber *)checked;
@end

NS_ASSUME_NONNULL_END
